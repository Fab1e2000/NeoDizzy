import Foundation
import Testing
@testable import NeoDizzy

@MainActor struct QQMusicWebLoginStoreTests {
    private let original = QQMusicCredential(musicID: "123", musicKey: "original-key", nickname: "Original")
    private let website = QQMusicCredential(musicID: "456", musicKey: "website-key")

    @Test func websiteLoginPublishesAndPersistsOnlyAfterValidation() async throws {
        let gate = WebLoginValidationGate()
        var writes: [Data?] = []
        var changes = 0
        let login = QQMusicLoginClient(transport: { try await gate.send($0) })
        let store = QQMusicStore(credential: original, restoreSaved: false, login: login, saveCredential: { writes.append($0) })
        store.accountChanged = { changes += 1 }
        let previousScope = store.cacheScope
        let cookies = try cookies(for: website)
        let work = Task { try await store.completeWebLogin(cookies: cookies) }
        await gate.waitForStart()

        #expect(store.credential == original)
        #expect(store.cacheScope == previousScope)
        #expect(store.revision == 0)
        #expect(writes.isEmpty)
        #expect(changes == 0)

        await gate.releaseSuccess()
        try await work.value

        #expect(store.credential == website)
        #expect(store.cacheScope != previousScope)
        #expect(store.revision == 1)
        #expect(writes.count == 1)
        let saved = try #require(writes.first ?? nil)
        #expect(try JSONDecoder().decode(QQMusicCredential.self, from: saved) == website)
        #expect(changes == 1)
    }

    @Test func networkFailurePreservesCurrentAccountAndSavedCredential() async throws {
        var writes: [Data?] = []
        var changes = 0
        let login = QQMusicLoginClient(transport: { _ in throw URLError(.notConnectedToInternet) })
        let store = QQMusicStore(credential: original, restoreSaved: false, login: login, saveCredential: { writes.append($0) })
        store.accountChanged = { changes += 1 }
        let previousScope = store.cacheScope
        let cookies = try cookies(for: website)

        await #expect(throws: URLError.self) { try await store.completeWebLogin(cookies: cookies) }

        #expect(store.credential == original)
        #expect(store.cacheScope == previousScope)
        #expect(store.revision == 0)
        #expect(writes.isEmpty)
        #expect(changes == 0)
    }

    @Test func unauthorizedSessionPreservesCurrentAccountAndSavedCredential() async throws {
        var writes: [Data?] = []
        var changes = 0
        let login = QQMusicLoginClient(transport: { request in
            (Data(#"{"code":1000}"#.utf8), HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!)
        })
        let store = QQMusicStore(credential: original, restoreSaved: false, login: login, saveCredential: { writes.append($0) })
        store.accountChanged = { changes += 1 }
        let previousScope = store.cacheScope
        let cookies = try cookies(for: website)

        await #expect(throws: QQMusicLoginError.server(1000)) { try await store.completeWebLogin(cookies: cookies) }

        #expect(store.credential == original)
        #expect(store.cacheScope == previousScope)
        #expect(store.revision == 0)
        #expect(writes.isEmpty)
        #expect(changes == 0)
    }

    @Test func cancelledValidationCannotCommitLateSuccess() async throws {
        let gate = WebLoginValidationGate()
        var writes: [Data?] = []
        var changes = 0
        let login = QQMusicLoginClient(transport: { try await gate.send($0) })
        let store = QQMusicStore(credential: original, restoreSaved: false, login: login, saveCredential: { writes.append($0) })
        store.accountChanged = { changes += 1 }
        let previousScope = store.cacheScope
        let cookies = try cookies(for: website)
        let work = Task { try await store.completeWebLogin(cookies: cookies) }
        await gate.waitForStart()

        work.cancel()
        await gate.releaseSuccess()
        await #expect(throws: CancellationError.self) { try await work.value }

        #expect(store.credential == original)
        #expect(store.cacheScope == previousScope)
        #expect(store.revision == 0)
        #expect(writes.isEmpty)
        #expect(changes == 0)
    }

    @Test func signOutCannotBeUndoneByLateValidationSuccess() async throws {
        let gate = WebLoginValidationGate()
        var writes: [Data?] = []
        var changes = 0
        let login = QQMusicLoginClient(transport: { try await gate.send($0) })
        let store = QQMusicStore(credential: original, restoreSaved: false, login: login, saveCredential: { writes.append($0) })
        store.accountChanged = { changes += 1 }
        let cookies = try cookies(for: website)
        let work = Task { try await store.completeWebLogin(cookies: cookies) }
        await gate.waitForStart()

        await store.signOut()
        #expect(store.credential == nil)
        #expect(store.cacheScope == "qqmusic/guest")
        #expect(store.revision == 1)
        #expect(writes == [nil])
        #expect(changes == 1)

        await gate.releaseSuccess()
        await #expect(throws: CancellationError.self) { try await work.value }

        #expect(store.credential == nil)
        #expect(store.cacheScope == "qqmusic/guest")
        #expect(store.revision == 1)
        #expect(writes == [nil])
        #expect(changes == 1)
    }

    @Test func deactivationRejectsLateValidationWithoutSavingAnotherAccount() async throws {
        let gate = WebLoginValidationGate()
        var writes: [Data?] = []
        var changes = 0
        let login = QQMusicLoginClient(transport: { try await gate.send($0) })
        let store = QQMusicStore(credential: original, restoreSaved: false, login: login, saveCredential: { writes.append($0) })
        store.accountChanged = { changes += 1 }
        let previousScope = store.cacheScope
        let cookies = try cookies(for: website)
        let work = Task { try await store.completeWebLogin(cookies: cookies) }
        await gate.waitForStart()

        store.deactivate()
        await gate.releaseSuccess()
        await #expect(throws: CancellationError.self) { try await work.value }

        #expect(!store.active)
        #expect(store.credential == original)
        #expect(store.cacheScope == previousScope)
        #expect(store.revision == 1)
        #expect(writes.isEmpty)
        #expect(changes == 0)
    }

    @Test func stagedCookieWritesValidateOnlyTheFinalStableCredentialOnce() async throws {
        let transport = WebLoginValidationRecorder()
        var writes: [Data?] = []
        var changes = 0
        let login = QQMusicLoginClient(transport: { await transport.send($0) })
        let store = QQMusicStore(credential: original, restoreSaved: false, login: login, saveCredential: { writes.append($0) })
        store.accountChanged = { changes += 1 }
        let complete = try cookies(for: website)
        let snapshots = [[], [complete[0]], complete, complete]
        var reads = 0

        try await store.completeWebLogin(readCookies: {
            #expect(store.credential == original)
            #expect(store.revision == 0)
            #expect(writes.isEmpty)
            let snapshot = snapshots[min(reads, snapshots.count - 1)]
            reads += 1
            return snapshot
        }, pause: {})

        #expect(reads == 4)
        #expect(await transport.requests.count == 1)
        #expect(store.credential == website)
        #expect(store.revision == 1)
        #expect(writes.count == 1)
        #expect(changes == 1)
    }

    @Test func cookieReadTimeoutKeepsCurrentAccountWithoutSendingValidation() async throws {
        let transport = WebLoginValidationRecorder()
        var writes: [Data?] = []
        var changes = 0
        let login = QQMusicLoginClient(transport: { await transport.send($0) })
        let store = QQMusicStore(credential: original, restoreSaved: false, login: login, saveCredential: { writes.append($0) })
        store.accountChanged = { changes += 1 }
        let previousScope = store.cacheScope
        let incomplete = try cookies(for: website).filter { $0.name == "qqmusic_uin" }
        var reads = 0

        await #expect(throws: QQMusicLoginError.musicAuthorizationPending) {
            try await store.completeWebLogin(readCookies: {
                reads += 1
                return incomplete
            }, pause: {})
        }

        #expect(reads == 8)
        #expect(await transport.requests.isEmpty)
        #expect(store.credential == original)
        #expect(store.cacheScope == previousScope)
        #expect(store.revision == 0)
        #expect(writes.isEmpty)
        #expect(changes == 0)
    }

    @Test(arguments: WebLoginReadInterruption.allCases, WebLoginReadSuspension.allCases)
    func interruptedCookieReadsCannotValidateOrReplaceAccount(
        interruption: WebLoginReadInterruption, suspension: WebLoginReadSuspension
    ) async throws {
        let gate = WebLoginStoreReadGate()
        let transport = WebLoginValidationRecorder()
        var writes: [Data?] = []
        var changes = 0
        let login = QQMusicLoginClient(transport: { await transport.send($0) })
        let store = QQMusicStore(credential: original, restoreSaved: false, login: login, saveCredential: { writes.append($0) })
        store.accountChanged = { changes += 1 }
        store.showsAccount = true
        let previousScope = store.cacheScope
        let websiteCookies = try cookies(for: website)
        let replacement = QQMusicCredential(musicID: "789", musicKey: "replacement-key")
        let replacementCookies = try cookies(for: replacement)
        var reads = 0
        let work = Task {
            try await store.completeWebLogin(readCookies: {
                reads += 1
                if suspension == .finalCookieRead, reads == 2 { await gate.wait() }
                // Intentionally ignores cancellation, as an in-flight WebKit callback may do.
                return websiteCookies
            }, pause: {
                if suspension == .pause { await gate.wait() }
            })
        }
        await gate.waitForStart()

        #expect(await transport.requests.isEmpty)
        #expect(writes.isEmpty)
        #expect(store.credential == original)
        switch interruption {
        case .closePresentation:
            store.showsAccount = false
            // The login view's onDisappear explicitly cancels its own task.
            work.cancel()
        case .cancelTask:
            work.cancel()
        case .deactivate:
            store.deactivate()
        case .signOut:
            await store.signOut()
        case .replacementLogin:
            try await store.completeWebLogin(readCookies: { replacementCookies }, pause: {})
        }
        await gate.release()
        await #expect(throws: CancellationError.self) { try await work.value }

        #expect(reads == (suspension == .pause ? 1 : 2))
        #expect(await transport.requests.count == (interruption == .replacementLogin ? 1 : 0))
        switch interruption {
        case .closePresentation, .cancelTask:
            #expect(store.credential == original)
            #expect(store.cacheScope == previousScope)
            #expect(store.revision == 0)
            #expect(writes.isEmpty)
            #expect(changes == 0)
        case .deactivate:
            #expect(!store.active)
            #expect(store.credential == original)
            #expect(store.cacheScope == previousScope)
            #expect(store.revision == 1)
            #expect(writes.isEmpty)
            #expect(changes == 0)
        case .signOut:
            #expect(store.credential == nil)
            #expect(store.cacheScope == "qqmusic/guest")
            #expect(store.revision == 1)
            #expect(writes == [nil])
            #expect(changes == 1)
        case .replacementLogin:
            #expect(store.credential == replacement)
            #expect(store.cacheScope != previousScope)
            #expect(store.revision == 1)
            #expect(writes.count == 1)
            let saved = try #require(writes.first ?? nil)
            #expect(try JSONDecoder().decode(QQMusicCredential.self, from: saved) == replacement)
            #expect(changes == 1)
        }
    }

    @Test(arguments: WebLoginAdoptionInterruption.allCases)
    func invalidatedAdoptionKeepsAPIStoreAndSavedAccountTogether(_ interruption: WebLoginAdoptionInterruption) async throws {
        let api = echoClient(credential: original)
        let gate = WebLoginAdoptionGate(api: api, heldIDs: [website.musicID])
        let login = successfulLoginClient()
        var saved: Data? = try JSONEncoder().encode(original)
        var writes = 0
        let store = QQMusicStore(credential: original, restoreSaved: false, api: api, login: login,
                                 adoptCredential: { await gate.adopt($0) }, saveCredential: { saved = $0; writes += 1 })
        let websiteCookies = try cookies(for: website)
        let work = Task { try await store.completeWebLogin(cookies: websiteCookies) }
        await gate.waitForAdoption(website.musicID)

        // The real API has adopted the credential, but the store has not published it.
        #expect(try await api.search(query: "test").first?.title.contains(website.musicKey) == true)
        #expect(store.credential == original)
        #expect(writes == 0)

        let replacement = QQMusicCredential(musicID: "789", musicKey: "replacement-key")
        let expected: QQMusicCredential?
        var followup: Task<Void, Error>?
        let started = WebLoginTaskStart()
        switch interruption {
        case .cancel:
            work.cancel()
            expected = original
        case .newerFailedLogin:
            await #expect(throws: QQMusicLoginError.loginRequired) {
                try await store.completeWebLogin(cookies: [])
            }
            expected = original
        case .signOut:
            followup = Task { started.signal(); await store.signOut() }
            await started.wait()
            expected = nil
        case .newerSuccessfulLogin:
            let replacementCookies = try cookies(for: replacement)
            followup = Task { started.signal(); try await store.completeWebLogin(cookies: replacementCookies) }
            await started.wait()
            expected = replacement
        }
        await gate.release(website.musicID)
        await #expect(throws: CancellationError.self) { try await work.value }
        try await followup?.value

        try await expectConsistentAccount(expected, store: store, saved: saved)
        let didPublish = interruption == .signOut || interruption == .newerSuccessfulLogin
        #expect(writes == (didPublish ? 1 : 0))
        #expect(store.revision == (didPublish ? 1 : 0))
    }

    @Test(arguments: [false, true])
    func newerLoginCannotAdoptUntilAnOlderTransactionFinishes(cancelNewest: Bool) async throws {
        let replacement = QQMusicCredential(musicID: "789", musicKey: "replacement-key")
        let api = echoClient(credential: original)
        let gate = WebLoginAdoptionGate(api: api, heldIDs: [], heldBeforeIDs: [website.musicID])
        var saved: Data? = try JSONEncoder().encode(original)
        var writes = 0
        let store = QQMusicStore(credential: original, restoreSaved: false, api: api, login: successfulLoginClient(),
                                 adoptCredential: { await gate.adopt($0) }, saveCredential: { saved = $0; writes += 1 })
        let websiteCookies = try cookies(for: website)
        let replacementCookies = try cookies(for: replacement)
        let first = Task { try await store.completeWebLogin(cookies: websiteCookies) }
        await gate.waitBeforeAdoption(website.musicID)
        #expect(try await api.search(query: "test").first?.title.contains(original.musicKey) == true)
        let started = WebLoginTaskStart()
        let second = Task { started.signal(); try await store.completeWebLogin(cookies: replacementCookies) }
        await started.wait()
        if cancelNewest { second.cancel() }
        await gate.releaseBeforeAdoption(website.musicID)
        await #expect(throws: CancellationError.self) { try await first.value }
        if cancelNewest {
            await #expect(throws: CancellationError.self) { try await second.value }
        } else { try await second.value }

        try await expectConsistentAccount(cancelNewest ? original : replacement, store: store, saved: saved)
        #expect(await gate.adoptedIDs == (cancelNewest ? [website.musicID] : [website.musicID, replacement.musicID]))
        #expect(writes == (cancelNewest ? 0 : 1))
        #expect(store.revision == (cancelNewest ? 0 : 1))
    }

    @Test func inFlightLogoutFinishesBeforeANewFailedLogin() async throws {
        let api = echoClient(credential: original)
        let gate = WebLoginAdoptionGate(api: api, heldIDs: ["guest"])
        var saved: Data? = try JSONEncoder().encode(original)
        var writes = 0
        let store = QQMusicStore(credential: original, restoreSaved: false, api: api, login: successfulLoginClient(),
                                 adoptCredential: { await gate.adopt($0) }, saveCredential: { saved = $0; writes += 1 })
        let logout = Task { await store.signOut() }
        await gate.waitForAdoption("guest")
        #expect(try await api.search(query: "test").first?.title == "guest")
        #expect(store.credential == original)

        let started = WebLoginTaskStart()
        let newLogin = Task { started.signal(); try await store.completeWebLogin(cookies: []) }
        await started.wait()
        await gate.release("guest")
        await logout.value
        await #expect(throws: QQMusicLoginError.loginRequired) { try await newLogin.value }

        try await expectConsistentAccount(nil, store: store, saved: saved)
        #expect(writes == 1)
        #expect(store.revision == 1)
    }

    private func successfulLoginClient() -> QQMusicLoginClient {
        QQMusicLoginClient(transport: { request in
            (Data(#"{"code":0}"#.utf8), HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!)
        })
    }

    private func echoClient(credential: QQMusicCredential?) -> QQMusicClient {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [QQMusicRequestEchoProtocol.self]
        configuration.httpCookieStorage = nil
        return QQMusicClient(session: URLSession(configuration: configuration), credential: credential)
    }

    private func expectConsistentAccount(_ expected: QQMusicCredential?, store: QQMusicStore, saved: Data?) async throws {
        #expect(store.credential == expected)
        #expect(try saved.map { try JSONDecoder().decode(QQMusicCredential.self, from: $0) } == expected)
        let cookie = try #require(await store.api.search(query: "test").first?.title)
        if let expected {
            #expect(cookie == "uin=\(expected.musicID); qqmusic_uin=\(expected.musicID); qm_keyst=\(expected.musicKey); qqmusic_key=\(expected.musicKey)")
        } else {
            #expect(cookie == "guest")
        }
    }

    private func cookies(for credential: QQMusicCredential) throws -> [HTTPCookie] {
        try [("qqmusic_uin", credential.musicID), ("qqmusic_key", credential.musicKey)].map { name, value in
            try #require(HTTPCookie(properties: [.name: name, .value: value, .domain: ".y.qq.com", .path: "/", .secure: "TRUE"]))
        }
    }
}

nonisolated enum WebLoginAdoptionInterruption: CaseIterable {
    case cancel, newerFailedLogin, signOut, newerSuccessfulLogin
}

/// Holds the return from a real API adoption, without delaying the API actor itself.
/// This exposes the interval before the main-actor store can publish the credential.
private actor WebLoginAdoptionGate {
    private let api: QQMusicClient
    private let heldIDs: Set<String>
    private let heldBeforeIDs: Set<String>
    private var pending: [String: (UUID, CheckedContinuation<UUID, Never>)] = [:]
    private var waiting: [String: CheckedContinuation<Void, Never>] = [:]
    private var pendingBefore: [String: CheckedContinuation<Void, Never>] = [:]
    private var waitingBefore: [String: CheckedContinuation<Void, Never>] = [:]
    private(set) var adoptedIDs: [String] = []

    init(api: QQMusicClient, heldIDs: Set<String>, heldBeforeIDs: Set<String> = []) {
        self.api = api
        self.heldIDs = heldIDs
        self.heldBeforeIDs = heldBeforeIDs
    }

    func adopt(_ credential: QQMusicCredential?) async -> UUID {
        let id = credential?.musicID ?? "guest"
        if heldBeforeIDs.contains(id) {
            await withCheckedContinuation { continuation in
                pendingBefore[id] = continuation
                waitingBefore.removeValue(forKey: id)?.resume()
            }
        }
        let token = await api.setCredential(credential)
        adoptedIDs.append(id)
        guard heldIDs.contains(id) else { return token }
        return await withCheckedContinuation { continuation in
            pending[id] = (token, continuation)
            waiting.removeValue(forKey: id)?.resume()
        }
    }

    func waitForAdoption(_ id: String) async {
        if pending[id] != nil { return }
        await withCheckedContinuation { waiting[id] = $0 }
    }

    func release(_ id: String) {
        guard let (token, continuation) = pending.removeValue(forKey: id) else { return }
        continuation.resume(returning: token)
    }

    func waitBeforeAdoption(_ id: String) async {
        if pendingBefore[id] != nil { return }
        await withCheckedContinuation { waitingBefore[id] = $0 }
    }

    func releaseBeforeAdoption(_ id: String) {
        pendingBefore.removeValue(forKey: id)?.resume()
    }
}

@MainActor private final class WebLoginTaskStart {
    private var started = false
    private var waiter: CheckedContinuation<Void, Never>?
    func signal() { started = true; waiter?.resume(); waiter = nil }
    func wait() async {
        if started { return }
        await withCheckedContinuation { waiter = $0 }
    }
}

nonisolated enum WebLoginReadInterruption: CaseIterable {
    case closePresentation, cancelTask, deactivate, signOut, replacementLogin
}

nonisolated enum WebLoginReadSuspension: CaseIterable {
    case pause, finalCookieRead
}

private actor WebLoginValidationRecorder {
    private(set) var requests: [URLRequest] = []

    func send(_ request: URLRequest) -> (Data, HTTPURLResponse) {
        requests.append(request)
        return (Data(#"{"code":0}"#.utf8), HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!)
    }
}

private actor WebLoginStoreReadGate {
    private var response: CheckedContinuation<Void, Never>?
    private var started: CheckedContinuation<Void, Never>?

    func wait() async {
        await withCheckedContinuation { continuation in
            response = continuation
            started?.resume()
            started = nil
        }
    }

    func waitForStart() async {
        if response != nil { return }
        await withCheckedContinuation { started = $0 }
    }

    func release() {
        response?.resume()
        response = nil
    }
}

/// Deliberately ignores task cancellation to model a response already in flight.
private actor WebLoginValidationGate {
    private var response: CheckedContinuation<Void, Never>?
    private var started: CheckedContinuation<Void, Never>?

    func send(_ request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        await withCheckedContinuation { continuation in
            response = continuation
            started?.resume()
            started = nil
        }
        return (Data(#"{"code":0}"#.utf8), HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!)
    }

    func waitForStart() async {
        if response != nil { return }
        await withCheckedContinuation { started = $0 }
    }

    func releaseSuccess() {
        response?.resume()
        response = nil
    }
}
