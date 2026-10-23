import Foundation
import Testing
@testable import NeoDizzy

@MainActor struct NeteaseSessionTests {
    private let account = NeteaseProfile(userId: 42, nickname: "test", avatarUrl: nil)

    @Test func pendingValidationNeverChangesSharedCookieAndLogoutWins() async throws {
        var continuation: CheckedContinuation<NeteaseProfile, Error>?
        let api = NeteaseAPI(client: NeteaseClient())
        api.client.cookie = "old"
        let store = NeteaseStore(api: api, validateCookie: { _ in
            try await withCheckedThrowingContinuation { continuation = $0 }
        }, saveCredential: { _ in })
        let task = Task { try await store.login(cookie: "candidate") }
        while continuation == nil { await Task.yield() }
        #expect(api.client.cookie == "old")
        store.logout()
        continuation!.resume(throwing: NeteaseError.response)
        await #expect(throws: (any Error).self) { try await task.value }
        #expect(api.client.cookie.isEmpty)
        #expect(store.profile == nil)
    }

    @Test func newerLoginWinsAgainstLateOlderValidation() async throws {
        var continuation: CheckedContinuation<NeteaseProfile, Error>?
        var saved: Data?
        let store = NeteaseStore(api: NeteaseAPI(client: NeteaseClient()), validateCookie: { cookie in
            if cookie == "older" {
                return try await withCheckedThrowingContinuation { continuation = $0 }
            }
            return account
        }, saveCredential: { saved = $0 })
        let older = Task { try await store.login(cookie: "older") }
        while continuation == nil { await Task.yield() }
        try await store.login(cookie: "newer")
        let committed = saved
        continuation!.resume(returning: account)
        await #expect(throws: CancellationError.self) { try await older.value }
        #expect(store.api.client.cookie == "newer")
        #expect(store.profile == account)
        #expect(saved == committed)
    }

    @Test func failedPersistenceDoesNotPublishCandidate() async {
        let api = NeteaseAPI(client: NeteaseClient())
        api.client.cookie = "old"
        let store = NeteaseStore(api: api, validateCookie: { _ in account }, saveCredential: { _ in throw NeteaseError.response })
        await #expect(throws: (any Error).self) { try await store.login(cookie: "new") }
        #expect(api.client.cookie == "old")
        #expect(store.profile == nil)
        store.logout()
        #expect(api.client.cookie.isEmpty)
        #expect(store.sessionError != nil)
    }

    @Test func suspendRejectsLateSuccessfulValidation() async {
        var continuation: CheckedContinuation<NeteaseProfile, Error>?
        let store = NeteaseStore(api: NeteaseAPI(client: NeteaseClient()), validateCookie: { _ in
            try await withCheckedThrowingContinuation { continuation = $0 }
        }, saveCredential: { _ in })
        let task = Task { try await store.login(cookie: "candidate") }
        while continuation == nil { await Task.yield() }
        store.suspend()
        continuation!.resume(returning: account)
        await #expect(throws: CancellationError.self) { try await task.value }
        #expect(store.profile == nil)
        #expect(store.api.client.cookie.isEmpty)
    }
}
