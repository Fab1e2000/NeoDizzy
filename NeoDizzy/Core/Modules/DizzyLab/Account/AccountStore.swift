import Foundation

/// 账号状态：是否登录、账号信息、登录是否已失效。凭据和账号信息一起存在钥匙串里。
@Observable @MainActor
final class AccountStore {
    private(set) var account: Account?
    /// 网站不再接受保存的 token，需要重新登录。账号信息保留，方便提示和重新登录。
    private(set) var isSessionExpired = false
    /// 从标签页的提示里打开登录页。
    var isLoginPresented = false
    var sessionError: String?
    @ObservationIgnored private let saveCredential: (Data?) throws -> Void
    @ObservationIgnored private var authenticating = false
    @ObservationIgnored private var authWaiters: [CheckedContinuation<Void, Never>] = []

    private func acquireAuth() async {
        if !authenticating { authenticating = true; return }
        await withCheckedContinuation { authWaiters.append($0) }
    }
    private func releaseAuth() {
        if authWaiters.isEmpty { authenticating = false }
        else { authWaiters.removeFirst().resume() }
    }

    var isLoggedIn: Bool { account != nil }

    @ObservationIgnored private let client: DizzyHTTPClient
    @ObservationIgnored private var tokenObserver: NSObjectProtocol?
    @ObservationIgnored private var revision = 0
    @ObservationIgnored private var isActive = true
    @ObservationIgnored private var logins: [UUID: Task<Account, Error>] = [:]
    @ObservationIgnored private var logouts: [UUID: Task<Void, Never>] = [:]
    @ObservationIgnored private let authenticate: (String, String) async throws -> Account
    @ObservationIgnored private let signOut: () async -> Void

    private static let keychainKey = "account"

    /// 钥匙串里保存的内容。
    private struct Stored: Codable {
        var account: Account
        var credentials: DizzyCredentials.Snapshot
        var isSessionExpired: Bool
    }

    init(client: DizzyHTTPClient = .shared,
         authenticate: ((String, String) async throws -> Account)? = nil,
         signOut: (() async -> Void)? = nil,
         saveCredential: @escaping (Data?) throws -> Void = { try KeychainStore.write($0, for: "account") }) {
        self.saveCredential = saveCredential
        self.client = client
        self.authenticate = authenticate ?? { try await DizzyAuth(client: client).login(username: $0, password: $1) }
        self.signOut = signOut ?? { await DizzyAuth(client: client).logout() }
        tokenObserver = NotificationCenter.default.addObserver(forName: .dizzyTokenRejected, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.markSessionExpired()
            }
        }
    }

    deinit {
        if let tokenObserver { NotificationCenter.default.removeObserver(tokenObserver) }
    }

    /// 启动时恢复上次的登录。
    func restore() {
        guard sessionError == nil, account == nil,
              let data = KeychainStore.data(for: Self.keychainKey),
              let stored = try? JSONDecoder().decode(Stored.self, from: data) else { return }
        client.credentials.restore(stored.credentials)
        account = stored.account
        isSessionExpired = stored.isSessionExpired || stored.credentials.token == nil
    }

    func login(username: String, password: String) async throws {
        guard isActive else { throw CancellationError() }
        revision += 1
        let generation = revision
        await acquireAuth()
        defer { releaseAuth() }
        try Task.checkCancellation()
        guard isActive, revision == generation else { throw CancellationError() }
        let previous = client.credentials.snapshot
        var published = false
        defer { if !published { client.credentials.restore(previous) } }
        let id = UUID(), authenticate = authenticate
        let task = Task { try await authenticate(username, password) }
        logins[id] = task
        defer { logins[id] = nil }
        let account = try await withTaskCancellationHandler {
            try await task.value
        } onCancel: { task.cancel() }
        try Task.checkCancellation()
        guard isActive, revision == generation else { throw CancellationError() }
        try saveCredential(JSONEncoder().encode(Stored(account: account, credentials: client.credentials.snapshot, isSessionExpired: false)))
        self.account = account
        isSessionExpired = false
        sessionError = nil
        published = true
        NotificationCenter.default.post(name: .dizzyAccountDidChange, object: nil)
    }

    func logout() async {
        guard isActive else { return }
        revision += 1
        await acquireAuth()
        defer { releaseAuth() }
        guard isActive else { return }
        let id = UUID(), signOut = signOut
        let task = Task { await signOut() }
        logouts[id] = task
        defer { logouts[id] = nil }
        await withTaskCancellationHandler {
            await task.value
        } onCancel: { task.cancel() }
        guard isActive else { return }
        account = nil
        isSessionExpired = false
        client.credentials.clear()
        do { try saveCredential(nil); sessionError = nil }
        catch { sessionError = "已退出当前会话，但凭据删除失败，重启可能恢复登录，请重试：\(error.localizedDescription)" }
        NotificationCenter.default.post(name: .dizzyAccountDidChange, object: nil)
    }

    /// Wait for the entire authentication workflow, including its credential cleanup.
    /// A newly enabled module must not restore credentials until these old tasks have exited.
    func suspend() async {
        isActive = false
        revision += 1
        isLoginPresented = false
        if let tokenObserver { NotificationCenter.default.removeObserver(tokenObserver) }
        tokenObserver = nil
        let loginTasks = Array(logins.values), logoutTasks = Array(logouts.values)
        loginTasks.forEach { $0.cancel() }
        logoutTasks.forEach { $0.cancel() }
        for task in loginTasks { _ = await task.result }
        for task in logoutTasks { await task.value }
        // Inner network tasks finish before their callers perform rollback. Join
        // the serialized transaction too, before another runtime may restore.
        await acquireAuth()
        releaseAuth()
    }

    private func markSessionExpired() {
        guard isActive, account != nil, !isSessionExpired else { return }
        isSessionExpired = true
        do { try save() } catch { sessionError = error.localizedDescription }
    }

    private func save() throws {
        guard let account else { return }
        let stored = Stored(account: account, credentials: client.credentials.snapshot, isSessionExpired: isSessionExpired)
        try saveCredential(JSONEncoder().encode(stored))
    }
}
