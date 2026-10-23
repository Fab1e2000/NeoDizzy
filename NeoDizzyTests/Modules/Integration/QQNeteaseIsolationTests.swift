import Foundation
import Testing
@testable import NeoDizzy

@MainActor struct QQNeteaseIsolationTests {
    @Test func disablingQQKeepsNeteaseRegisteredAndDisablingNeteaseKeepsQQRegistered() async {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let suite = "QQMusicIsolation.\(UUID())"
        let defaults = UserDefaults(suiteName: suite)!
        defer {
            defaults.removePersistentDomain(forName: suite)
            try? FileManager.default.removeItem(at: folder)
        }
        let local = PlatformRegistration(descriptor: LocalLibraryModule.metadata, canDisable: false) {
            PlatformRuntime(module: LocalLibraryModule(library: $0.offlineLibrary))
        }
        for disabled in [ModuleID.qqmusic, .netease] {
            defaults.removeObject(forKey: "moduleServices.disabled.v1")
            let services = AppServices(registrations: [QQMusicModule.registration, NeteaseModule.registration, local], defaults: defaults,
                                       library: OfflineLibraryStore(libraryRoot: folder), storageDirectory: folder,
                                       migrateDownloads: { _ in nil })
            await services.setEnabled(false, for: disabled)
            let remaining = disabled == .qqmusic ? "netease" : "qqmusic"
            #expect(services.modules.contains(providerID: remaining))
            #expect(!services.modules.contains(providerID: disabled.rawValue))
            let track = Track(discID: "42", number: "1", title: "Song", artists: "Artist", albumTitle: "Album", coverURL: nil,
                              remoteSource: .init(providerID: remaining, itemID: "42"))
            #expect(services.resolver.audioCacheKey(for: track) != nil)
            await services.setEnabled(false, for: disabled == .qqmusic ? .netease : .qqmusic)
        }
    }
}
