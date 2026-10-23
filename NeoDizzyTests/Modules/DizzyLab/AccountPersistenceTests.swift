import Foundation
import Testing
@testable import NeoDizzy

@MainActor struct AccountPersistenceTests {
    private struct Failure: Error {}
    @Test func suspendJoinsCredentialRollbackBeforeReturning() async {
        let client = DizzyHTTPClient()
        client.credentials.setToken("previous")
        var pending: CheckedContinuation<Account, Never>?
        var saveCalled = false
        let store = AccountStore(client: client, authenticate: { _, _ in
            client.credentials.setToken("candidate")
            return await withCheckedContinuation { pending = $0 }
        }, signOut: {}, saveCredential: { _ in saveCalled = true; throw Failure() })
        let login = Task { try await store.login(username: "test", password: "test") }
        while pending == nil { await Task.yield() }
        store.isLoginPresented = true
        let suspension = Task { await store.suspend() }
        while store.isLoginPresented { await Task.yield() }
        pending!.resume(returning: Account(userID: 1, nickname: "test", avatarURL: nil))
        await suspension.value
        #expect(client.credentials.snapshot.token == "previous")
        client.credentials.setToken("new-runtime")
        _ = await login.result
        #expect(client.credentials.snapshot.token == "new-runtime")
        #expect(!saveCalled)
    }

    @Test func failedSaveRestoresPreviousCredentialAndDoesNotPublish() async {
        let client = DizzyHTTPClient()
        client.credentials.setToken("previous")
        let store = AccountStore(client: client, authenticate: { _, _ in
            client.credentials.setToken("candidate")
            return Account(userID: 1, nickname: "test", avatarURL: nil)
        }, signOut: {}, saveCredential: { _ in throw Failure() })
        await #expect(throws: Failure.self) { try await store.login(username: "test", password: "test") }
        #expect(store.account == nil)
        #expect(client.credentials.snapshot.token == "previous")
        await store.logout()
        #expect(store.account == nil)
        #expect(client.credentials.snapshot.token == nil)
        #expect(store.sessionError != nil)
    }
}
