import Foundation
import Synchronization

/// 登录凭据：网页和 POST 操作用的会话 Cookie，`/apis/*` 用的 token（见 docs/SITE_API.md「概况」）。
/// 这里只保存在内存里；登录后由 AccountStore 连同账号信息写进钥匙串，启动时再恢复。
nonisolated final class DizzyCredentials: Sendable {
    nonisolated struct Snapshot: Codable, Equatable, Sendable {
        var cookies: [StoredCookie] = []
        var token: String?
    }

    private let state = Mutex(Snapshot())

    var token: String? {
        state.withLock { $0.token }
    }

    var snapshot: Snapshot {
        state.withLock { $0 }
    }

    func setToken(_ token: String?) {
        state.withLock { $0.token = token }
    }

    func restore(_ snapshot: Snapshot) {
        state.withLock { $0 = snapshot }
    }

    func clear() {
        state.withLock { $0 = Snapshot() }
    }

    func hasCookie(named name: String, now: Date = .now) -> Bool {
        state.withLock { $0.cookies.contains { $0.name == name && !$0.isExpired(at: now) } }
    }

    /// 请求头 `Cookie` 的值；没有有效 Cookie 时为空。
    func cookieHeader(now: Date = .now) -> String? {
        let pairs = state.withLock { snapshot in
            snapshot.cookies.filter { !$0.isExpired(at: now) }.map { "\($0.name)=\($0.value)" }
        }
        return pairs.isEmpty ? nil : pairs.joined(separator: "; ")
    }

    /// 记下响应里的 `Set-Cookie`：同名覆盖；已过期的（例如退出登录时网站清掉的 sessionid）直接删除。
    func store(_ cookies: [HTTPCookie], now: Date = .now) {
        guard !cookies.isEmpty else { return }
        state.withLock { snapshot in
            for cookie in cookies {
                snapshot.cookies.removeAll { $0.name == cookie.name }
                let stored = StoredCookie(name: cookie.name, value: cookie.value, expires: cookie.expiresDate)
                if !stored.isExpired(at: now), !stored.value.isEmpty {
                    snapshot.cookies.append(stored)
                }
            }
        }
    }
}

/// 只保留发请求要用的字段。所有 Cookie 都属于 www.dizzylab.net，不记域名和路径。
nonisolated struct StoredCookie: Codable, Equatable, Sendable {
    let name: String
    let value: String
    /// 为空表示会话 Cookie（关闭浏览器即失效）；App 里一直保留到退出登录。
    let expires: Date?

    func isExpired(at date: Date) -> Bool {
        expires.map { $0 <= date } ?? false
    }
}

nonisolated extension Notification.Name {
    /// 登录、退出登录后发出。缓存了播放地址等和账号有关内容的地方据此清掉旧数据。
    static let dizzyAccountDidChange = Notification.Name("NeoDizzy.accountDidChange")
    /// 网站不再接受当前 token（带 token 的请求返回错误页）。
    static let dizzyTokenRejected = Notification.Name("NeoDizzy.tokenRejected")
}
