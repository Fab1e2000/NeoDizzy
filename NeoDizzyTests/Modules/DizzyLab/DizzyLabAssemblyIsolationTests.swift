import Foundation
import SwiftUI
import Testing
@testable import NeoDizzy

@MainActor struct DizzyLabAssemblyIsolationTests {
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



    @Test func realAssembliesDoNotRequireTheOtherPlatform() {
        for platform in [DizzyLabModule.registration] {
            let fixture = Fixture()
            defer { fixture.clean() }
            let services = fixture.make([platform, local])
            let provider = platform.providerID ?? platform.descriptor.id.rawValue
            let other = provider == "netease" ? "dizzylab" : "netease"
            #expect(services.modules.descriptors.map(\.id) == [platform.descriptor.id, .localLibrary])
            #expect(services.modules.contains(providerID: provider))
            #expect(!services.modules.contains(providerID: other))
            #expect(services.downloads.isAvailable(provider))
            #expect(!services.downloads.isAvailable(other))
            #expect(services.modules.collectionRoute(providerID: provider, kind: "album", itemID: "42") != nil)
            #expect(services.modules.collectionRoute(providerID: other, kind: "album", itemID: "42") == nil)
            #expect(services.resolver.audioCacheKey(for: song(other)) == nil)
            // No restore, sync, stream, or real account write is performed here.
        }
    }
}
