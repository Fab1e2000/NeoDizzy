import Foundation
import SwiftUI
import Testing
@testable import NeoDizzy

@MainActor
struct AppServicesIsolationTests {
    private final class Fixture {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        let suite = "AppServicesIsolation.\(UUID())"
        let defaults: UserDefaults
        init() { defaults = UserDefaults(suiteName: suite)! }
        func make(_ registrations: [PlatformRegistration]) -> AppServices {
            AppServices(registrations: registrations, defaults: defaults,
                        library: OfflineLibraryStore(libraryRoot: folder), storageDirectory: folder.appendingPathComponent("State"), migrateDownloads: { _ in nil })
        }
        func clean() {
            defaults.removePersistentDomain(forName: suite)
            try? FileManager.default.removeItem(at: folder)
        }
    }
    private var local: PlatformRegistration {
        PlatformRegistration(descriptor: LocalLibraryModule.metadata, canDisable: false) {
            PlatformRuntime(module: LocalLibraryModule(library: $0.offlineLibrary))
        }
    }
    private func song(_ provider: String) -> Track {
        Track(discID: "42", number: "1", title: "Song", artists: "Artist", albumTitle: "Album", coverURL: nil,
              remoteSource: RemoteTrackSource(providerID: provider, itemID: "1"))
    }



    @Test func localOnlyAssemblyHasNoOnlineCapabilitiesAndCannotBeDisabled() async {
        let fixture = Fixture()
        defer { fixture.clean() }
        let services = fixture.make([local])
        #expect(services.modules.descriptors.map(\.id) == [.localLibrary])
        for provider in ["netease", "dizzylab"] {
            #expect(!services.downloads.isAvailable(provider))
            #expect(!services.modules.contains(providerID: provider))
            #expect(services.resolver.audioCacheKey(for: song(provider)) == nil)
        }
        await services.setEnabled(false, for: .localLibrary)
        #expect(services.isEnabled(.localLibrary))
        #expect(services.moduleSettings.visibleModules == [.localLibrary])
    }

    private final class Probe {
        var created = 0
        var synced = 0
        var shutdowns = 0
        var streamReads = 0
        var releaseShutdown: CheckedContinuation<Void, Never>?
        var suspendShutdown = false
    }
    private final class TestModule: AppModule {
        let descriptor: ModuleDescriptor
        init(_ id: String) { descriptor = .init(id: ModuleID(rawValue: id), title: id, systemImage: "music.note") }
        func rootView() -> AnyView { AnyView(EmptyView()) }
        func destination(for route: AppRoute) -> AnyView? { nil }
        func collectionRoute(kind: String, itemID: String) -> AppRoute? {
            AppRoute(moduleID: descriptor.id, destination: itemID, title: itemID)
        }
    }
    private func registration(_ id: String, probe: Probe) -> PlatformRegistration {
        let moduleID = ModuleID(rawValue: id)
        return PlatformRegistration(descriptor: .init(id: moduleID, title: id, systemImage: "music.note")) { services in
            probe.created += 1
            services.resolver.register(id, provider: PlaybackProvider(stream: { _ in
                probe.streamReads += 1
                return RemotePlaybackSource(url: URL(string: "https://example.invalid/\(id).mp3")!, expiresAt: .distantFuture, isPreview: false)
            }, cacheKey: { .init(trackID: $0.id, scope: "test", quality: "test") }))
            services.accountLibrary.register(id) { _ in probe.synced += 1 }
            services.libraryProviders.register(id, provider: .init(title: id))
            return PlatformRuntime(module: TestModule(id), shutdown: {
                probe.shutdowns += 1
                if probe.suspendShutdown {
                    await withCheckedContinuation { probe.releaseShutdown = $0 }
                }
            })
        }
    }

    @Test func disablingRevokesCapabilitiesBeforeCleanupAndKeepsOtherSourceAlive() async throws {
        let fixture = Fixture()
        defer { fixture.clean() }
        let first = Probe(), second = Probe()
        first.suspendShutdown = true
        let services = fixture.make([registration("first", probe: first), registration("second", probe: second), local])
        let disabling = Task { await services.setEnabled(false, for: ModuleID(rawValue: "first")) }
        while first.releaseShutdown == nil { await Task.yield() }
        #expect(!services.isEnabled(ModuleID(rawValue: "first")))
        #expect(!services.modules.contains(providerID: "first"))
        #expect(services.resolver.audioCacheKey(for: song("first")) == nil)
        #expect(!services.libraryProviders.settings().keys.contains("first"))
        #expect(services.modules.contains(providerID: "second"))
        #expect(services.resolver.audioCacheKey(for: song("second")) != nil)
        #expect(try await services.resolver.stream(for: song("second"), preferLocal: false) == URL(string: "https://example.invalid/second.mp3"))
        #expect(second.streamReads == 1)
        await services.syncAccountLibrary(force: true)
        #expect(first.synced == 0)
        #expect(second.synced == 1)
        first.releaseShutdown?.resume()
        await disabling.value
        #expect(first.shutdowns == 1)
        #expect(second.shutdowns == 0)
        first.suspendShutdown = false
        await services.setEnabled(true, for: ModuleID(rawValue: "first"))
        #expect(first.created == 2)
        #expect(services.modules.contains(providerID: "first"))
        #expect(services.resolver.audioCacheKey(for: song("first")) != nil)
        #expect(services.modules.descriptors.filter { $0.id.rawValue == "first" }.count == 1)
    }

    @Test func disabledStateSurvivesReassemblyAndHidingDoesNotDisableServices() async {
        let fixture = Fixture()
        defer { fixture.clean() }
        let probe = Probe()
        let registrations = [registration("optional", probe: probe), local]
        let services = fixture.make(registrations)
        let id = ModuleID(rawValue: "optional")
        services.moduleSettings.setVisible(false, for: id)
        #expect(services.isEnabled(id))
        #expect(services.modules.contains(providerID: "optional"))
        #expect(services.resolver.audioCacheKey(for: song("optional")) != nil)
        await services.setEnabled(false, for: id)
        let reopened = fixture.make(registrations)
        #expect(!reopened.isEnabled(id))
        #expect(reopened.modules.descriptors.map(\.id) == [.localLibrary])
        #expect(probe.created == 1)
        await reopened.setEnabled(true, for: id)
        let enabledAgain = fixture.make(registrations)
        #expect(enabledAgain.isEnabled(id))
        #expect(enabledAgain.modules.contains(providerID: "optional"))
    }
}
