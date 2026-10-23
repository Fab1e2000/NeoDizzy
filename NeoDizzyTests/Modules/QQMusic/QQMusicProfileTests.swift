import Foundation
import Testing
@testable import NeoDizzy

@MainActor struct QQMusicProfileTests {
    private let account = QQMusicCredential(musicID: "123", musicKey: "fixture-key")
    private let profile = #"{"code":0,"data":{"creator":{"nick":"测试昵称","headpic":"http://thirdqq.qlogo.cn/g?b=qq&k=fixture&s=100"}}}"#

    private func client(_ body: String) -> QQMusicLoginClient {
        QQMusicLoginClient(transport: { request in
            (Data(body.utf8), HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!)
        })
    }

    @Test func validatedProfileRetainsNicknameAndHTTPSAvatar() async throws {
        let credential = try await client(profile).validate(account)
        #expect(credential.nickname == "测试昵称")
        #expect(credential.avatarURL?.absoluteString == "https://thirdqq.qlogo.cn/g?b=qq&k=fixture&s=100")
        #expect(credential.musicKey == account.musicKey && credential.musicID == account.musicID)
        let persisted = try JSONDecoder().decode(QQMusicCredential.self, from: JSONEncoder().encode(credential))
        #expect(persisted == credential)
        let legacy = try JSONDecoder().decode(QQMusicCredential.self, from: Data(#"{"musicID":"123","musicKey":"fixture-key","loginType":2}"#.utf8))
        #expect(legacy.avatarURL == nil)
    }

    @Test func malformedOptionalProfileDoesNotRejectValidSession() async throws {
        var previous = account
        previous.nickname = "已有昵称"
        previous.avatarURL = URL(string: "https://qlogo.cn/old")
        for body in [#"{"code":0}"#, #"{"code":0,"data":{"creator":{"nick":42,"headpic":"file:///tmp/avatar"}}}"#] {
            #expect(try await client(body).validate(previous) == previous)
        }
        #expect(QQMusicLoginClient.avatarURL("//qlogo.cn/image")?.scheme == "https")
        for value in ["", "relative.jpg", "javascript:foo", "data:image/png;base64,abc", "https://user:pass@qlogo.cn/a"] {
            #expect(QQMusicLoginClient.avatarURL(value) == nil)
        }
    }

    @Test func refreshEnrichesRestoredAccountWithoutResettingPlaybackSession() async throws {
        var saved: Data?
        var accountChanges = 0
        let store = QQMusicStore(credential: account, restoreSaved: false, login: client(profile), saveCredential: { saved = $0 })
        store.accountChanged = { accountChanges += 1 }
        let scope = store.cacheScope, revision = store.revision, libraryRevision = store.library.revision
        await store.refreshProfile()
        #expect(store.credential?.avatarURL != nil)
        #expect(store.accountTitle == "测试昵称")
        #expect(QQMusicModule(store: store).accountEntry?.avatarURL == store.credential?.avatarURL)
        #expect(store.cacheScope == scope && store.revision == revision)
        #expect(store.library.revision == libraryRevision && accountChanges == 0)
        let data = try #require(saved)
        #expect(try JSONDecoder().decode(QQMusicCredential.self, from: data) == store.credential)
    }

    @Test func refreshFailurePreservesKnownAccountAndDoesNotPersist() async {
        var saved = 0
        var candidate = account
        candidate.avatarURL = URL(string: "https://qlogo.cn/old")
        let store = QQMusicStore(credential: candidate, restoreSaved: false, login: client(#"{"code":1000}"#), saveCredential: { _ in saved += 1 })
        await store.refreshProfile()
        #expect(store.credential == candidate && saved == 0)
    }

    @Test(arguments: [false, true]) func lateProfileCannotReviveLogoutOrDisabledModule(disable: Bool) async {
        let gate = QQProfileGate()
        var saved: [Data?] = []
        let login = QQMusicLoginClient(transport: { try await gate.send($0) })
        let store = QQMusicStore(credential: account, restoreSaved: false, login: login, saveCredential: { saved.append($0) })
        let work = Task { await store.refreshProfile() }
        await gate.waitForStart()
        if disable { store.deactivate() } else { await store.signOut() }
        let count = saved.count
        await gate.release(profile)
        await work.value
        #expect(saved.count == count)
        #expect(store.credential?.avatarURL == nil)
        #expect(disable ? !store.active : store.credential == nil)
    }

    @Test func backgroundProfileCannotCancelInteractiveValidation() async throws {
        let gate = QQProfileGate()
        let login = QQMusicLoginClient(transport: { try await gate.send($0) })
        let validation = Task { try await login.validate(account) }
        await gate.waitForStart()
        _ = try await login.refreshProfile(account)
        await gate.release(profile)
        #expect(try await validation.value.avatarURL != nil)
    }

    @Test func lateProfileCannotOverwriteNewAccount() async throws {
        let gate = QQProfileGate()
        var saved: [Data?] = []
        let store = QQMusicStore(credential: account, restoreSaved: false,
                                login: QQMusicLoginClient(transport: { try await gate.send($0) }),
                                saveCredential: { saved.append($0) })
        let refresh = Task { await store.refreshProfile() }
        await gate.waitForStart()
        let cookies = try ["qqmusic_uin": "456", "qqmusic_key": "new-key"].map { name, value in
            try #require(HTTPCookie(properties: [.domain: "y.qq.com", .path: "/", .name: name, .value: value]))
        }
        try await store.completeWebLogin(cookies: cookies)
        await gate.release(profile)
        await refresh.value
        #expect(store.credential?.musicID == "456")
        #expect(store.credential?.avatarURL == nil)
        #expect(saved.count == 1)
    }
}

private actor QQProfileGate {
    private var started = false
    private var waiting: CheckedContinuation<String, Never>?
    func send(_ request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        let body: String
        if !started {
            started = true
            body = await withCheckedContinuation { waiting = $0 }
        } else { body = #"{"code":0}"# }
        return (Data(body.utf8), HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!)
    }
    func waitForStart() async { while waiting == nil { await Task.yield() } }
    func release(_ body: String) { waiting?.resume(returning: body); waiting = nil }
}
