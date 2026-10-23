import Foundation
import Testing
@testable import NeoDizzy

@MainActor struct QQMusicPersistenceTests {
    private struct Failure: Error {}
    @Test func failedLoginSaveRollsBackAdoptedClient() async {
        let login = QQMusicLoginClient(transport: { request in
            (Data("{\"code\":0}".utf8), HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!)
        })
        let store = QQMusicStore(restoreSaved: false, login: login, saveCredential: { _ in throw Failure() })
        await #expect(throws: Failure.self) {
            try await store.restoreCredential(QQMusicCredential(musicID: "123", musicKey: "test"))
        }
        #expect(store.credential == nil)
        #expect(await store.api.credential == nil)
    }

    @Test func deletionFailureStillSignsOutAndCanBeRetried() async {
        var fails = true
        let store = QQMusicStore(credential: QQMusicCredential(musicID: "123", musicKey: "test"), restoreSaved: false,
                                 saveCredential: { _ in if fails { throw Failure() } })
        await store.signOut()
        #expect(store.credential == nil)
        #expect(store.sessionError != nil)
        fails = false
        await store.signOut()
        #expect(store.credential == nil)
        #expect(store.sessionError == nil)
    }
}
