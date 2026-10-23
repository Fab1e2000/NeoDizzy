import Foundation
import Observation

@Observable @MainActor
final class NeteaseStore {
    let api: NeteaseAPI
    let library: NeteaseLibrary
    let radio: NeteaseRadioSession
    let reporter: NeteasePlaybackReporter
    var playbackSettings: NeteasePlaybackSettings { api.playbackSettings }
    private(set) var profile: NeteaseProfile?
    private(set) var revision = 0
    var showsAccount = false
    var showsLogin = false
    var accountChanged: (() -> Void)?
    private let credentialKey = "netease.session.v1"

    var sessionError: String?
    @ObservationIgnored private var loginGeneration = UUID()
    @ObservationIgnored private let validateCookie: (String) async throws -> NeteaseProfile
    @ObservationIgnored private let saveCredential: (Data?) throws -> Void

    init(api injectedAPI: NeteaseAPI? = nil,
         validateCookie: ((String) async throws -> NeteaseProfile)? = nil,
         saveCredential: @escaping (Data?) throws -> Void = { try KeychainStore.write($0, for: "netease.session.v1") }) {
        let client = injectedAPI?.client ?? NeteaseClient()
        let api = injectedAPI ?? NeteaseAPI(client: client)
        self.api = api
        self.saveCredential = saveCredential
        self.validateCookie = validateCookie ?? { cookie in
            let candidate = client.isolatedClient(cookie: cookie)
            return try await NeteaseAPI(client: candidate).profile()
        }
        reporter = NeteasePlaybackReporter(api: api)
        library = NeteaseLibrary(api: api)
        radio = NeteaseRadioSession { try await api.radio().map(\.track) }
        if injectedAPI == nil, let data = KeychainStore.data(for: credentialKey), let saved = try? JSONDecoder().decode(Session.self, from: data) {
            client.cookie = saved.cookie
            profile = saved.profile
        }
        library.reset(userID: profile?.userId)
    }
    private struct Session: Codable { let cookie: String; let profile: NeteaseProfile }
    func login(cookie: String) async throws {
        let generation = UUID()
        loginGeneration = generation
        let account = try await validateCookie(cookie)
        try Task.checkCancellation()
        guard loginGeneration == generation else { throw CancellationError() }
        let data = try JSONEncoder().encode(Session(cookie: cookie, profile: account))
        // No suspension between persistence and publication: MainActor serializes
        // login, logout and backup restoration as one synchronous transaction.
        try saveCredential(data)
        api.client.cookie = cookie
        reporter.reset()
        profile = account
        library.reset(userID: account.userId)
        radio.reset()
        revision += 1
        sessionError = nil
        accountChanged?()
        showsLogin = false
    }
    /// Revoke in-memory work while retaining the account credential for re-enabling.
    func suspend() {
        loginGeneration = UUID()
        revision += 1
        reporter.reset()
        library.reset(userID: nil)
        radio.reset()
        showsAccount = false
        showsLogin = false
    }
    func logout() {
        loginGeneration = UUID()
        reporter.reset()
        library.reset(userID: nil)
        radio.reset()
        api.client.cookie = ""
        profile = nil
        do {
            try saveCredential(nil)
            sessionError = nil
        } catch {
            sessionError = "已退出当前会话，但无法删除保存的凭据。重启后可能恢复登录，请重试清除：\(error.localizedDescription)"
        }
        revision += 1
        accountChanged?()
        showsAccount = false
    }
}
