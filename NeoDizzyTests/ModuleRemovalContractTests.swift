import Foundation
import SwiftUI
import Testing
@testable import NeoDizzy

/// Runs unchanged after any platform source directory has physically disappeared.
@MainActor struct ModuleRemovalContractTests {
    private final class Rig {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("ModuleRemovalContract.\(UUID())")
        let suite = "ModuleRemovalContract.\(UUID())"
        let defaults: UserDefaults
        init() { defaults = UserDefaults(suiteName: suite)! }
        func services(_ registrations: [PlatformRegistration]) -> AppServices {
            AppServices(registrations: registrations, defaults: defaults,
                        library: OfflineLibraryStore(libraryRoot: directory.appendingPathComponent("Audio")),
                        storageDirectory: directory.appendingPathComponent("State"), migrateDownloads: { _ in nil })
        }
        func clean() {
            defaults.removePersistentDomain(forName: suite)
            try? FileManager.default.removeItem(at: directory)
        }
    }
    private var local: PlatformRegistration {
        PlatformRegistration(descriptor: LocalLibraryModule.metadata, canDisable: false) {
            PlatformRuntime(module: LocalLibraryModule(library: $0.offlineLibrary))
        }
    }
    private func song(_ provider: String) -> Track {
        Track(discID: "collection", number: "1", title: provider, artists: "Fixture", albumTitle: "Fixture", coverURL: nil,
              remoteSource: .init(providerID: provider, itemID: "1"))
    }

    @Test func compiledCompositionExposesEveryRemainingModuleWithoutNetworkRequests() throws {
        let rig = Rig(); defer { rig.clean() }
        let registrations = AppComposition.registrations
        let actualIDs = Set(registrations.map { $0.descriptor.id.rawValue })
        if let expected = ProcessInfo.processInfo.environment["REMOVAL_EXPECTED_MODULES"] {
            print("ModuleRemovalContract expected=\(expected) actual=\(actualIDs.sorted().joined(separator: ","))")
            #expect(!expected.isEmpty, "Matrix must provide its expected module set")
            #expect(actualIDs == Set(expected.split(separator: ",").map(String.init)))
        }
        #expect(registrations.filter { !$0.canDisable }.map(\.descriptor.id) == [.localLibrary])
        let services = rig.services(registrations)
        #expect(Set(services.modules.descriptors.map(\.id)) == Set(registrations.map(\.descriptor.id)))
        #expect(Set(services.moduleSettings.visibleModules) == Set(registrations.map(\.descriptor.id)))
        #expect(Set(services.modules.searchSections(query: "fixture", in: services.moduleSettings.visibleSearchModules).map(\.id)) == Set(registrations.map(\.descriptor.id)))
        for registration in registrations {
            let id = registration.descriptor.id
            #expect(services.isEnabled(id))
            _ = services.modules.rootView(for: id)
            if registration.canDisable {
                let provider = registration.providerID ?? id.rawValue
                #expect(services.modules.contains(providerID: provider))
                #expect(services.downloads.isAvailable(provider))
                #expect(services.modules.accountEntry(for: id) != nil)
                let route = try #require(services.modules.collectionRoute(providerID: provider, kind: "album", itemID: "42"))
                #expect(route.moduleID == id)
                _ = services.modules.destination(for: route)
                #expect(services.libraryProviders.settings().keys.contains(provider))
            }
        }
        #expect(!services.modules.contains(providerID: "absent-fixture"))
        #expect(!services.downloads.isAvailable("absent-fixture"))
        #expect(services.modules.collectionRoute(providerID: "absent-fixture", kind: "album", itemID: "42") == nil)
    }

    private final class Probe {
        var created = 0
        var restored = 0
        var synced = 0
        var stopped = 0
        var streamRequests = 0
        var searches: [String] = []
    }
    private final class Module: AppModule {
        let descriptor: ModuleDescriptor
        let provider: String
        let probe: Probe
        init(id: ModuleID, provider: String, probe: Probe) {
            self.descriptor = .init(id: id, title: provider, systemImage: "music.note")
            self.provider = provider; self.probe = probe
        }
        var libraryOrigin: LibraryOrigin { .init(rawValue: provider, label: provider, systemImage: "music.note") }
        var accountEntry: ModuleAccountEntry? { .init(title: provider, avatarURL: nil, isSignedIn: true) }
        func rootView() -> AnyView { AnyView(Text(provider)) }
        func destination(for route: AppRoute) -> AnyView? { AnyView(Text(route.title)) }
        func searchSection(query: String) -> AnyView? { probe.searches.append(query); return AnyView(Text(query)) }
        func collectionRoute(kind: String, itemID: String) -> AppRoute? {
            AppRoute(moduleID: descriptor.id, destination: itemID, title: itemID)
        }
    }
    private final class Download: DownloadProvider {
        let id: String
        init(_ id: String) { self.id = id }
        func title(_ request: Data) -> String { id }
        func identity(_ request: Data) -> String { id }
        func plan(_ request: Data) async throws -> [DownloadTransfer] { [] }
        func source(_ transfer: DownloadTransfer) async throws -> DownloadSource? { nil }
        func finalize(_ file: URL, metadata: Data, staging: URL) async throws -> PreparedDownload {
            throw DownloadFailure.unavailable
        }
    }
    private func registration(_ number: Int, probe: Probe) -> PlatformRegistration {
        let provider = "fixture-provider-\(number)"
        let id = ModuleID(rawValue: "fixture-slot-\(number)")
        return PlatformRegistration(descriptor: .init(id: id, title: provider, systemImage: "music.note"), providerID: provider) { services in
            probe.created += 1
            services.downloads.register(Download(provider))
            services.resolver.register(provider, provider: PlaybackProvider(stream: { _ in
                probe.streamRequests += 1
                return .init(url: URL(string: "https://example.invalid/\(provider).mp3")!, expiresAt: .distantFuture, isPreview: false)
            }, cacheKey: { .init(trackID: $0.id, scope: provider, quality: "fixture") }))
            services.accountLibrary.register(provider, account: { "fixture-account" }) { _ in probe.synced += 1 }
            services.libraryProviders.register(provider, provider: .init(title: provider, onlineSongs: { _ in [] },
                                                                       exportSettings: { ["quality": "fixture"] }))
            return PlatformRuntime(module: Module(id: id, provider: provider, probe: probe), restore: { probe.restored += 1 },
                                   shutdown: { probe.stopped += 1 })
        }
    }

    @Test(arguments: [0, 1, 2])
    func hostSupportsZeroOneOrTwoOnlineModulesAndRevokesOnlyTheRemovedProvider(count: Int) async throws {
        let rig = Rig(); defer { rig.clean() }
        let probes = (0..<count).map { _ in Probe() }
        let registrations = probes.enumerated().map { registration($0.offset, probe: $0.element) } + [local]
        let services = rig.services(registrations)
        let installed = Set(registrations.map(\.descriptor.id))
        #expect(Set(services.modules.descriptors.map(\.id)) == installed)
        #expect(Set(services.modules.searchSections(query: "first", in: Array(installed)).map(\.id)) == installed)
        await services.syncAccountLibrary(force: true)
        for number in 0..<count {
            let provider = "fixture-provider-\(number)"
            #expect(probes[number].created == 1 && probes[number].synced == 1)
            #expect(probes[number].searches == ["first"])
            #expect(services.downloads.isAvailable(provider))
            #expect(try await services.resolver.stream(for: song(provider), preferLocal: false) == URL(string: "https://example.invalid/\(provider).mp3"))
            #expect(probes[number].streamRequests == 1)
            try await services.accountLibrary.sync(provider, account: "fixture-account") { commit in
                try commit([.init(providerID: provider, kind: .album, itemID: "1", title: provider, subtitle: "", coverURL: nil, firstSeen: .now)])
            }
        }
        await services.setEnabled(false, for: .localLibrary)
        #expect(services.isEnabled(.localLibrary))
        guard let removed = registrations.first, removed.canDisable else {
            #expect(services.libraryProviders.settings().isEmpty)
            #expect(services.accountLibrary.collections.isEmpty)
            return
        }
        let removedProvider = try #require(removed.providerID)
        await services.setEnabled(false, for: removed.descriptor.id)
        #expect(!services.downloads.isAvailable(removedProvider))
        #expect(services.resolver.audioCacheKey(for: song(removedProvider)) == nil)
        #expect(!services.modules.contains(providerID: removedProvider))
        #expect(!services.libraryProviders.settings().keys.contains(removedProvider))
        #expect(!services.accountLibrary.collections.contains { $0.providerID == removedProvider })
        #expect(probes[0].stopped == 1)
        #expect(services.accountLibrary.state(removedProvider).collections.count == 1, "Removal must preserve persisted account data")
        if count == 2 {
            #expect(services.downloads.isAvailable("fixture-provider-1"))
            #expect(services.accountLibrary.collections.map(\.providerID) == ["fixture-provider-1"])
            #expect(try await services.resolver.stream(for: song("fixture-provider-1"), preferLocal: false) == URL(string: "https://example.invalid/fixture-provider-1.mp3"))
            #expect(probes[1].streamRequests == 1, "Other source's cached URL must survive")
            #expect(probes[1].stopped == 0)
        }
        let remaining = installed.subtracting([removed.descriptor.id])
        #expect(Set(services.modules.searchSections(query: "second", in: Array(installed)).map(\.id)) == remaining)
        let reopened = rig.services(registrations)
        #expect(!reopened.isEnabled(removed.descriptor.id))
        #expect(Set(reopened.modules.descriptors.map(\.id)) == remaining)
        await services.setEnabled(true, for: removed.descriptor.id)
        #expect(services.downloads.isAvailable(removedProvider))
        #expect(probes[0].created == 2 && probes[0].restored == 1)
        #expect(services.accountLibrary.collections.contains { $0.providerID == removedProvider })
    }
}
