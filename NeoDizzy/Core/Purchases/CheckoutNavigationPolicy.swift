import Foundation

/// 收银台只能访问网站和支付宝；导航结果本身不能证明支付成功。
nonisolated enum CheckoutNavigationPolicy {
    enum Decision: Equatable, Sendable {
        case allow
        case openAlipay
        case block
    }

    static func decision(for url: URL, isMainFrame: Bool = true) -> Decision {
        let scheme = url.scheme?.lowercased()
        if scheme == "alipays" || scheme == "alipay" { return .openAlipay }
        if !isMainFrame, url.absoluteString == "about:blank" { return .allow }
        guard isSecureWebURL(url), let host = url.host?.lowercased() else { return .block }
        if host == "www.dizzylab.net" || host == "alipay.com" || host.hasSuffix(".alipay.com") {
            return .allow
        }
        return .block
    }

    static func isCheckoutURL(_ url: URL) -> Bool {
        isSiteURL(url) && url.path.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
            == "albums/checkout_alipay"
    }

    static func isSiteReturn(_ url: URL) -> Bool {
        isSiteURL(url) && !isCheckoutURL(url)
    }

    /// 不传递 API token，也不使用宽泛的 dizzylab.net Cookie 域名。
    static func cookies(from snapshot: DizzyCredentials.Snapshot, now: Date = .now) -> [HTTPCookie] {
        snapshot.cookies.compactMap { cookie in
            guard !cookie.isExpired(at: now), !cookie.name.isEmpty, !cookie.value.isEmpty else { return nil }
            var properties: [HTTPCookiePropertyKey: Any] = [
                .name: cookie.name,
                .value: cookie.value,
                .domain: "www.dizzylab.net",
                .path: "/",
                .secure: "TRUE",
            ]
            if let expires = cookie.expires { properties[.expires] = expires }
            return HTTPCookie(properties: properties)
        }
    }

    private static func isSiteURL(_ url: URL) -> Bool {
        isSecureWebURL(url) && url.host?.lowercased() == "www.dizzylab.net"
    }

    private static func isSecureWebURL(_ url: URL) -> Bool {
        url.scheme?.lowercased() == "https" && url.user == nil && url.password == nil
            && (url.port == nil || url.port == 443)
    }
}
