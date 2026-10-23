import Foundation
import Testing
@testable import NeoDizzy

@MainActor struct QQMusicModuleTests {
    @Test func accountChangesHaveDistinctCacheScopesAndDisabledStoreCannotSignIn() async throws {
        var persisted: Data? = Data("existing".utf8)
        let guestStore = QQMusicStore(restoreSaved: false, saveCredential: { _ in })
        let first = QQMusicCredential(musicID: "123", musicKey: "first-key", loginType: 2, nickname: "Test")
        let store = QQMusicStore(credential: first, restoreSaved: false, saveCredential: { persisted = $0 })
        let firstScope = store.cacheScope
        #expect(firstScope != guestStore.cacheScope)
        #expect(!firstScope.contains("first-key"))
        let renewed = QQMusicStore(credential: QQMusicCredential(musicID: "123", musicKey: "next-key"), restoreSaved: false,
                                   saveCredential: { _ in })
        #expect(renewed.cacheScope != firstScope)
        await store.signOut()
        #expect(store.cacheScope == guestStore.cacheScope)
        #expect(persisted == nil)
        await store.shutdown()
        await #expect(throws: CancellationError.self) { try await store.completeWebLogin(cookies: []) }
        #expect(store.credential == nil)
        #expect(persisted == nil)
    }

    @Test func qqCanRunAloneAndItsDisableDoesNotRemoveAnotherProvider() async throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let suite = "QQMusicModuleTests.\(UUID())"
        let defaults = UserDefaults(suiteName: suite)!
        defer {
            defaults.removePersistentDomain(forName: suite)
            try? FileManager.default.removeItem(at: folder)
        }
        let local = PlatformRegistration(descriptor: LocalLibraryModule.metadata, canDisable: false) {
            PlatformRuntime(module: LocalLibraryModule(library: $0.offlineLibrary))
        }
        let services = AppServices(registrations: [QQMusicModule.registration, local], defaults: defaults,
                                   library: OfflineLibraryStore(libraryRoot: folder), storageDirectory: folder,
                                   migrateDownloads: { _ in nil })
        let track = Track(discID: "album-mid", number: "1", title: "Song", artists: "Artist", albumTitle: "Album", coverURL: nil,
                          remoteSource: .init(providerID: "qqmusic", itemID: "song-mid"))
        #expect(services.modules.contains(providerID: "qqmusic"))
        #expect(!services.modules.contains(providerID: "netease"))
        #expect(services.resolver.audioCacheKey(for: track) != nil)
        #expect(services.modules.collectionRoute(providerID: "qqmusic", kind: "album", itemID: "album-mid") != nil)
        await services.setEnabled(false, for: .qqmusic)
        #expect(services.resolver.audioCacheKey(for: track) == nil)
        #expect(services.modules.descriptors.map(\.id) == [.localLibrary])
        await services.setEnabled(true, for: .qqmusic)
        #expect(services.resolver.audioCacheKey(for: track) != nil)
        #expect(services.isEnabled(.localLibrary))
        await services.setEnabled(false, for: .qqmusic)
    }


}
