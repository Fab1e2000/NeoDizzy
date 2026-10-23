// QQ website credential validation adapted from L-1124/QQMusicApi (GPL-3.0-or-later).
// See THIRD_PARTY_NOTICES.md for source revision and attribution.
import Foundation

nonisolated enum QQMusicLoginError: LocalizedError, Equatable {
    case loginRequired, musicAuthorizationPending, accountIdentifierMissing, ambiguousCookies, invalidResponse, server(Int), http(Int)

    var errorDescription: String? {
        switch self {
        case .loginRequired: "请先在 QQ 音乐官网完成登录，再点击完成"
        case .musicAuthorizationPending: "已识别到账号，正在等待 QQ 音乐授权完成，请稍后再试"
        case .accountIdentifierMissing: "已收到 QQ 音乐授权，账号信息仍在同步，请稍后再试"
        case .ambiguousCookies: "网页登录状态尚未同步完成，请稍后再试"
        case .invalidResponse: "QQ 音乐登录验证返回了无法识别的数据，请重试"
        case .server(let code): "QQ 音乐登录验证失败（\(code)），请返回官网重新登录"
        case .http(let code): "QQ 音乐登录验证请求失败（HTTP \(code)），请稍后重试"
        }
    }
}

private final class QQMusicLoginRedirectDelegate: NSObject, URLSessionTaskDelegate, @unchecked Sendable {
    nonisolated func urlSession(_ session: URLSession, task: URLSessionTask,
                               willPerformHTTPRedirection response: HTTPURLResponse,
                               newRequest request: URLRequest,
                               completionHandler: @escaping (URLRequest?) -> Void) {
        // Never forward a manually assembled music-session Cookie header to a redirect.
        completionHandler(nil)
    }
}

nonisolated private struct QQMusicWebsiteValidation: Decodable {
    let code: Int
}

/// Uses a temporary session to validate website cookies before the store commits them.
/// No request here changes the module's active API credential or global cookie jar.
actor QQMusicLoginClient {
    typealias Transport = @Sendable (URLRequest) async throws -> (Data, HTTPURLResponse)
    private let transport: Transport
    private var enabled = true
    private var generation = 0
    private var requests: [UUID: Task<(Data, HTTPURLResponse), Error>] = [:]

    init(transport: Transport? = nil) {
        if let transport { self.transport = transport }
        else {
            let configuration = URLSessionConfiguration.ephemeral
            configuration.httpCookieStorage = nil
            configuration.httpShouldSetCookies = false
            configuration.urlCache = nil
            configuration.timeoutIntervalForRequest = 30
            let session = URLSession(configuration: configuration, delegate: QQMusicLoginRedirectDelegate(), delegateQueue: nil)
            self.transport = { request in
                let (data, response) = try await session.data(for: request)
                guard let response = response as? HTTPURLResponse else { throw QQMusicLoginError.invalidResponse }
                return (data, response)
            }
        }
    }

    func setEnabled(_ enabled: Bool) {
        guard self.enabled != enabled else { return }
        self.enabled = enabled
        reset()
    }

    func cancel() { reset() }

    private func reset() {
        generation += 1
        requests.values.forEach { $0.cancel() }
        requests.removeAll()
    }

    /// Reads the session visible to the fixed QQ Music website, so a parent-domain
    /// account cookie can accompany a website-domain music key. QQ SSO tickets
    /// never stand in for a QQ Music key, and conflicting visible values are not
    /// resolved by cookie order or by silently preferring one account family.
    nonisolated static func credential(from cookies: [HTTPCookie], now: Date = Date()) throws -> QQMusicCredential {
        let applicable = cookies.filter { cookie in
            appliesToWebsite(cookie) && (cookie.expiresDate.map { $0 > now } ?? true) && !cookie.value.isEmpty
        }
        let keys = Set(applicable.filter { $0.name == "qqmusic_key" || $0.name == "qm_keyst" }.map(\.value))
        guard keys.count <= 1 else { throw QQMusicLoginError.ambiguousCookies }
        guard let key = keys.first else {
            let hasAccount = applicable.contains { cookie in
                ["qqmusic_uin", "uin", "wxuin"].contains(cookie.name)
                    && normalizedID(cookie.value, allowQQPrefix: cookie.name == "uin") != nil
            }
            throw hasAccount ? QQMusicLoginError.musicAuthorizationPending : QQMusicLoginError.loginRequired
        }
        guard isSafeCookieValue(key) else { throw QQMusicLoginError.loginRequired }

        // A W_X ticket belongs to a WeChat music account. A browser can retain a
        // separate QQ SSO uin, which must not replace wxuin. qqmusic_uin is the
        // music-specific alias for either login type and must agree if present.
        let isWechat = key.hasPrefix("W_X")
        let accountNames = isWechat ? ["wxuin", "qqmusic_uin"] : ["qqmusic_uin", "uin"]
        var ids: Set<String> = []
        for name in accountNames {
            let values = Set(applicable.filter { $0.name == name }.map(\.value))
            for value in values {
                guard let id = normalizedID(value, allowQQPrefix: name == "uin") else { throw QQMusicLoginError.loginRequired }
                ids.insert(id)
            }
        }
        guard ids.count <= 1 else { throw QQMusicLoginError.ambiguousCookies }
        guard let id = ids.first else { throw QQMusicLoginError.accountIdentifierMissing }
        return QQMusicCredential(musicID: id, musicKey: key, loginType: isWechat ? 1 : 2)
    }

    nonisolated private static func appliesToWebsite(_ cookie: HTTPCookie) -> Bool {
        // The target is https://y.qq.com/, not whichever login frame or callback
        // happens to be displayed. Only qq.com is its allowed parent domain;
        // child hosts (such as c6.y.qq.com) and other QQ services do not match.
        let rawDomain = cookie.domain.lowercased()
        let isDomainCookie = rawDomain.hasPrefix(".")
        let domain = isDomainCookie ? String(rawDomain.dropFirst()) : rawDomain
        // Foundation represents Domain=qq.com as .qq.com; a bare qq.com is
        // host-only and cannot supply cookies to its y.qq.com child host.
        guard domain == "y.qq.com" || (isDomainCookie && domain == "qq.com") else { return false }
        // For the root URL the only matching cookie path is /. A /portal or
        // /n/ryqq cookie is unrelated even though it shares the website's host.
        return cookie.path == "/"
    }

    func validate(_ candidate: QQMusicCredential) async throws -> QQMusicCredential {
        try await profile(candidate, superseding: true)
    }

    /// A background profile read must never cancel an interactive login validation.
    func refreshProfile(_ candidate: QQMusicCredential) async throws -> QQMusicCredential {
        try await profile(candidate, superseding: false)
    }

    private func profile(_ candidate: QQMusicCredential, superseding: Bool) async throws -> QQMusicCredential {
        guard enabled else { throw CancellationError() }
        try Task.checkCancellation()
        guard let id = Self.normalizedID(candidate.musicID), Self.isSafeCookieValue(candidate.musicKey) else {
            throw QQMusicLoginError.loginRequired
        }
        if superseding { reset() }
        let epoch = generation
        var result = candidate
        result.musicID = id
        // This is QQMusicApi LoginApi.check_expired's WEB contract. A public
        // profile lookup without this session-bound request is not login proof.
        var url = URLComponents(string: "https://c6.y.qq.com/rsc/fcgi-bin/fcg_get_profile_homepage.fcg")!
        url.queryItems = [
            "g_tk": String(Self.hash33(result.musicKey)), "format": "json",
            "inCharset": "utf-8", "outCharset": "utf-8", "notice": "0", "cid": "205360838",
            "needNewCode": "0", "loginUin": id, "hostUin": "0", "userid": id, "reqfrom": "1"
        ].sorted { $0.key < $1.key }.map { URLQueryItem(name: $0.key, value: $0.value) }
        var request = URLRequest(url: url.url!)
        request.setValue("https://y.qq.com/", forHTTPHeaderField: "Referer")
        request.setValue("Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15 Version/17.0 Safari/605.1.15", forHTTPHeaderField: "User-Agent")
        request.setValue("uin=\(id); qqmusic_uin=\(id); qm_keyst=\(result.musicKey); qqmusic_key=\(result.musicKey)", forHTTPHeaderField: "Cookie")
        request.httpShouldHandleCookies = false
        let (data, _) = try await send(request, epoch: epoch)
        guard let response = try? JSONDecoder().decode(QQMusicWebsiteValidation.self, from: data) else {
            throw QQMusicLoginError.invalidResponse
        }
        guard response.code == 0 else { throw QQMusicLoginError.server(response.code) }
        if let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
           let data = root["data"] as? [String: Any], let creator = data["creator"] as? [String: Any] {
            if let nickname = creator["nick"] as? String, !nickname.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                result.nickname = nickname.trimmingCharacters(in: .whitespacesAndNewlines)
            }
            if let url = Self.avatarURL(creator["headpic"]) { result.avatarURL = url }
        }
        return result
    }

    nonisolated static func avatarURL(_ value: Any?) -> URL? {
        guard let raw = value as? String else { return nil }
        var text = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if text.hasPrefix("//") { text = "https:" + text }
        guard var url = URLComponents(string: text), let scheme = url.scheme?.lowercased(),
              ["http", "https"].contains(scheme), let host = url.host, !host.isEmpty,
              url.user == nil, url.password == nil else { return nil }
        url.scheme = "https"
        return url.url
    }

    private func send(_ request: URLRequest, epoch: Int) async throws -> (Data, HTTPURLResponse) {
        guard enabled, generation == epoch else { throw CancellationError() }
        try Task.checkCancellation()
        let id = UUID()
        let transport = transport
        let task = Task { try await transport(request) }
        requests[id] = task
        defer { requests[id] = nil }
        let result: (Data, HTTPURLResponse)
        do {
            result = try await withTaskCancellationHandler { try await task.value } onCancel: { task.cancel() }
        } catch {
            guard enabled, generation == epoch, !Task.isCancelled else { throw CancellationError() }
            throw error
        }
        guard enabled, generation == epoch else { throw CancellationError() }
        try Task.checkCancellation()
        guard result.1.url?.scheme == "https", result.1.url?.host == "c6.y.qq.com",
              result.1.url?.path == request.url?.path else { throw QQMusicLoginError.invalidResponse }
        guard (200..<300).contains(result.1.statusCode) else { throw QQMusicLoginError.http(result.1.statusCode) }
        return result
    }

    nonisolated private static func normalizedID(_ text: String, allowQQPrefix: Bool = false) -> String? {
        let digits = allowQQPrefix && text.hasPrefix("o") ? String(text.dropFirst()) : text
        guard !digits.isEmpty, digits.utf8.allSatisfy({ $0 >= 48 && $0 <= 57 }),
              let number = UInt64(digits), number > 0 else { return nil }
        return String(number)
    }

    nonisolated private static func isSafeCookieValue(_ text: String) -> Bool {
        !text.isEmpty && text.utf8.allSatisfy { byte in
            byte >= 0x21 && byte <= 0x7e && ![0x22, 0x2c, 0x3b, 0x5c].contains(byte)
        }
    }

    nonisolated private static func hash33(_ text: String) -> UInt32 {
        text.utf16.reduce(UInt32(5381)) { ($0 &* 33) &+ UInt32($1) } & 0x7FFF_FFFF
    }
}
