import Foundation

/// 账号状态：是否登录、账号信息、登录是否已失效。凭据和账号信息一起存在钥匙串里。
@Observable
final class AccountStore {
    private(set) var account: Account?
    /// 网站不再接受保存的 token，需要重新登录。账号信息保留，方便提示和重新登录。
    private(set) var isSessionExpired = false
    /// 从标签页的提示里打开登录页。
    var isLoginPresented = false

    var isLoggedIn: Bool { account != nil }

    @ObservationIgnored private let client: DizzyHTTPClient
    @ObservationIgnored private var tokenObserver: NSObjectProtocol?

    private static let keychainKey = "account"

    /// 钥匙串里保存的内容。
    private struct Stored: Codable {
        var account: Account
        var credentials: DizzyCredentials.Snapshot
        var isSessionExpired: Bool
    }

    init(client: DizzyHTTPClient = .shared) {
        self.client = client
        tokenObserver = NotificationCenter.default.addObserver(forName: .dizzyTokenRejected, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.markSessionExpired()
            }
        }
    }

    /// 启动时恢复上次的登录。
    func restore() {
        guard account == nil,
              let data = KeychainStore.data(for: Self.keychainKey),
              let stored = try? JSONDecoder().decode(Stored.self, from: data) else { return }
        client.credentials.restore(stored.credentials)
        account = stored.account
        isSessionExpired = stored.isSessionExpired || stored.credentials.token == nil
    }

    func login(username: String, password: String) async throws {
        let account = try await DizzyAuth(client: client).login(username: username, password: password)
        self.account = account
        isSessionExpired = false
        save()
        NotificationCenter.default.post(name: .dizzyAccountDidChange, object: nil)
    }

    func logout() async {
        await DizzyAuth(client: client).logout()
        account = nil
        isSessionExpired = false
        KeychainStore.set(nil, for: Self.keychainKey)
        NotificationCenter.default.post(name: .dizzyAccountDidChange, object: nil)
    }

    private func markSessionExpired() {
        guard account != nil, !isSessionExpired else { return }
        isSessionExpired = true
        save()
    }

    private func save() {
        guard let account else { return }
        let stored = Stored(account: account, credentials: client.credentials.snapshot, isSessionExpired: isSessionExpired)
        KeychainStore.set(try? JSONEncoder().encode(stored), for: Self.keychainKey)
    }
}
