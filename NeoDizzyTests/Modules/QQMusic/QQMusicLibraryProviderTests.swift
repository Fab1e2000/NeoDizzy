import Foundation
import Testing
@testable import NeoDizzy

@MainActor struct QQMusicLibraryProviderTests {
    @Test func restoreValidatesBeforePublishingAndDoesNotReplaceExistingAccount() async throws {
        let login = QQMusicLoginClient(transport: { request in
            (Data(#"{"code":0}"#.utf8), HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!)
        })
        var writes: [Data?] = []
        let store = QQMusicStore(restoreSaved: false, login: login, saveCredential: { writes.append($0) })
        let registry = LibraryProviderRegistry()
        registry.registerQQMusic(store)
        let account = QQMusicCredential(musicID: "1152921504606846976", musicKey: "fixture-key", loginType: 1)
        let encoded = String(decoding: try JSONEncoder().encode(account), as: UTF8.self)
        _ = await registry.restore(["qqmusic": encoded])
        #expect(store.credential == account)
        #expect(store.library.accountID == account.musicID)
        #expect(writes.count == 1)
        #expect(try JSONDecoder().decode(QQMusicCredential.self, from: Data(try #require(registry.credentials()["qqmusic"]).utf8)) == account)
        _ = await registry.restore(["qqmusic": "invalid"])
        #expect(store.credential == account)
        #expect(writes.count == 1)
        registry.unregister("qqmusic")
        #expect(registry.credentials().isEmpty)
        #expect(registry.settings().isEmpty)
    }

    @Test func failedRestoreLeavesGuestAndNoCredentialBackup() async {
        let login = QQMusicLoginClient(transport: { _ in throw URLError(.notConnectedToInternet) })
        var writes = 0
        let store = QQMusicStore(restoreSaved: false, login: login, saveCredential: { _ in writes += 1 })
        let registry = LibraryProviderRegistry()
        registry.registerQQMusic(store)
        _ = await registry.restore(["qqmusic": #"{"musicID":"123","musicKey":"fixture-key","loginType":2}"#])
        #expect(store.credential == nil)
        #expect(writes == 0)
        #expect(registry.credentials().isEmpty)
    }
}
