import CryptoKit
import Foundation
import Observation

/// Credentials and request lifetimes belong exclusively to this platform.
@Observable @MainActor final class QQMusicStore {
    let api: QQMusicClient
    let login: QQMusicLoginClient
    let radio: QQMusicRadioSession
    let library: QQMusicLibrary
    let playbackSettings = QQMusicPlaybackSettings()
    private(set) var credential: QQMusicCredential?
    private(set) var active = true
    private(set) var revision = 0
    var showsAccount = false
    var sessionError: String?
    @ObservationIgnored var accountChanged: (() -> Void)?
    @ObservationIgnored private var accountGeneration = UUID()
    @ObservationIgnored private let saveCredential: (Data?) throws -> Void
    @ObservationIgnored private let adoptCredential: @Sendable (QQMusicCredential?) async -> UUID
    @ObservationIgnored private var committingCredential = false
    @ObservationIgnored private var credentialCommitWaiters: [CheckedContinuation<Void, Never>] = []
    @ObservationIgnored private var profileTask: Task<Void, Never>?
    @ObservationIgnored private var profileRequestID: UUID?
    @ObservationIgnored private var pendingSignOut: Task<Void, Never>?

    init(credential: QQMusicCredential? = nil, restoreSaved: Bool = true, api: QQMusicClient? = nil, login: QQMusicLoginClient? = nil,
         adoptCredential: (@Sendable (QQMusicCredential?) async -> UUID)? = nil,
         saveCredential: @escaping (Data?) throws -> Void = { try KeychainStore.write($0, for: "qqmusic.credential.v1") }) {
        let saved = restoreSaved ? KeychainStore.data(for: "qqmusic.credential.v1") : nil
        let value = credential ?? saved.flatMap { try? JSONDecoder().decode(QQMusicCredential.self, from: $0) }
        self.credential = value
        let client = api ?? QQMusicClient(credential: value)
        self.api = client
        self.library = QQMusicLibrary(api: client)
        self.library.reset(accountID: value?.musicID)
        self.radio = QQMusicRadioSession { try await client.guessSongs().map(\.track) }
        self.login = login ?? QQMusicLoginClient()
        self.adoptCredential = adoptCredential ?? { await client.setCredential($0) }
        self.saveCredential = saveCredential
    }

    var accountTitle: String { credential?.nickname ?? credential?.musicID ?? "未登录" }
    var cacheScope: String {
        guard let credential else { return "qqmusic/guest" }
        let digest = SHA256.hash(data: Data(credential.musicKey.utf8)).map { String(format: "%02x", $0) }.joined()
        return "qqmusic/\(credential.musicID)/\(digest)"
    }

    /// Refresh display metadata without changing the playback or library session.
    func refreshProfile() async {
        guard active, let candidate = credential else { return }
        if let profileTask { await profileTask.value; return }
        let generation = accountGeneration, requestID = UUID()
        profileRequestID = requestID
        let task = Task { [weak self] in
            guard let self else { return }
            defer {
                if profileRequestID == requestID { profileTask = nil; profileRequestID = nil }
            }
            do {
                let updated = try await login.refreshProfile(candidate)
                try Task.checkCancellation()
                guard active, accountGeneration == generation, credential == candidate,
                      profileRequestID == requestID, updated != candidate else { return }
                let data = try JSONEncoder().encode(updated)
                try saveCredential(data)
                credential = updated
            } catch { /* Keep the current account and its last known profile on failure. */ }
        }
        profileTask = task
        await task.value
    }

    private func cancelProfileRefresh() {
        profileTask?.cancel()
        profileTask = nil
        profileRequestID = nil
    }

    func completeWebLogin(cookies: [HTTPCookie]) async throws {
        try await completeWebLogin { _ in
            try QQMusicLoginClient.credential(from: cookies)
        }
    }

    func completeWebLogin(
        readCookies: () async -> [HTTPCookie],
        pause: () async throws -> Void = { try await Task.sleep(for: .milliseconds(400)) }
    ) async throws {
        try await completeWebLogin { generation in
            try await QQMusicWebLoginReader.credential(readCookies: {
                try checkLoginGeneration(generation)
                let cookies = await readCookies()
                try checkLoginGeneration(generation)
                return cookies
            }, pause: {
                try await pause()
                try checkLoginGeneration(generation)
            })
        }
    }

    private func completeWebLogin(resolveCredential: (UUID) async throws -> QQMusicCredential) async throws {
        // An explicit logout must finish before a new attempt can supersede it.
        // In particular, an incomplete new website session cannot undo logout.
        if let pendingSignOut { await pendingSignOut.value }
        try Task.checkCancellation()
        guard active else { throw CancellationError() }
        let generation = UUID()
        accountGeneration = generation
        cancelProfileRefresh()
        let candidate = try await resolveCredential(generation)
        try checkLoginGeneration(generation)
        // Validate using an isolated client, leaving the current account untouched on failure.
        let verified = try await login.validate(candidate)
        try checkLoginGeneration(generation)
        try await commit(verified, generation: generation)
    }

    /// Backup restoration reuses the same validation and serialized commit as web login.
    func restoreCredential(_ value: QQMusicCredential) async throws {
        guard credential == nil else { return }
        try await completeWebLogin { _ in value }
    }

    private func checkLoginGeneration(_ generation: UUID) throws {
        try Task.checkCancellation()
        guard active, accountGeneration == generation else { throw CancellationError() }
    }

    private func commit(_ value: QQMusicCredential?, generation: UUID) async throws {
        await acquireCredentialCommit()
        defer { releaseCredentialCommit() }
        try checkLoginGeneration(generation)
        let data = try value.map { try JSONEncoder().encode($0) }
        let token = await adoptCredential(value)
        do {
            try checkLoginGeneration(generation)
            if value != nil { try saveCredential(data) }
        } catch {
            // The API may have adopted this account before cancellation or another
            // login reached the main actor. Restore the last published account,
            // only if no newer API adoption has superseded our token.
            await api.restoreCredential(credential, ifCurrent: token)
            throw error
        }
        credential = value
        if value == nil {
            do { try saveCredential(nil); sessionError = nil }
            catch { sessionError = "已退出当前会话，但凭据删除失败，重启可能恢复登录，请重试：\(error.localizedDescription)" }
        } else { sessionError = nil }
        radio.reset()
        library.reset(accountID: value?.musicID)
        // Publish only after the client has adopted this account. Page tasks must not
        // start against the previous account and then be cancelled by setCredential.
        revision += 1
        accountChanged?()
    }

    // Keep adoption, publication and any rollback in one serial transaction.
    // Reading cookies and validating the website remain independently cancellable.
    private func acquireCredentialCommit() async {
        if !committingCredential {
            committingCredential = true
            return
        }
        await withCheckedContinuation { credentialCommitWaiters.append($0) }
    }

    private func releaseCredentialCommit() {
        if credentialCommitWaiters.isEmpty { committingCredential = false }
        else { credentialCommitWaiters.removeFirst().resume() }
    }

    func signOut() async {
        if let pendingSignOut {
            await pendingSignOut.value
            return
        }
        guard active else { return }
        let generation = UUID()
        accountGeneration = generation
        cancelProfileRefresh()
        let task = Task { _ = try? await commit(nil, generation: generation) }
        pendingSignOut = task
        await task.value
        pendingSignOut = nil
    }

    func deactivate() {
        accountGeneration = UUID()
        cancelProfileRefresh()
        radio.reset()
        library.reset(accountID: nil)
        active = false
        revision += 1
        showsAccount = false
        accountChanged = nil
    }

    func shutdown() async {
        deactivate()
        async let apiStopped: Void = api.setEnabled(false)
        async let loginStopped: Void = login.setEnabled(false)
        _ = await (apiStopped, loginStopped)
    }
}
