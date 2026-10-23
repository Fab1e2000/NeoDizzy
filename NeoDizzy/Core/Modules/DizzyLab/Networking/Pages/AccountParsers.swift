import Foundation
import SwiftSoup

/// 登录页 `/albums/login/`：表单里的 csrfmiddlewaretoken，以及登录失败时网页给出的原因。
nonisolated enum LoginPageParser {
    static func csrfToken(_ html: String) throws -> String {
        try HTML.parsing("login") {
            let document = try HTML.document(html, page: "login")
            guard let token = try document.select("form[method=post] input[name=csrfmiddlewaretoken]").first()?.attr("value"),
                  !token.isEmpty else {
                throw DizzyError.parsing("login")
            }
            return token
        }
    }

    /// 登录失败时页面上的提示。实测网站用 Bootstrap 的 `.alert`（「抱歉！登录信息错误」，带一个 × 关闭按钮），
    /// 另外兼容几种常见的 Django 写法。找不到时返回空，由调用方给出通用说明。
    static func errorMessage(_ html: String) -> String? {
        guard let document = try? SwiftSoup.parse(html) else { return nil }
        for selector in [".alert", ".errorlist", ".invalid-feedback", "form .text-danger", ".messages"] {
            guard let element = try? document.select(selector).first() else { continue }
            // 关闭按钮的「×」不是提示内容。
            _ = try? element.select("button, .close").remove()
            if let text = try? element.text().trimmingCharacters(in: .whitespaces), !text.isEmpty {
                return text
            }
        }
        return nil
    }

    /// 返回的仍是带密码框的登录页，说明没有登录成功。
    static func isLoginForm(_ html: String) -> Bool {
        guard let document = try? SwiftSoup.parse(html) else { return false }
        return (try? document.select("form[method=post] input[name=password]").first()) != nil
    }
}

/// 登录后的首页：导航栏下拉菜单里有「个人信息」`/u/<id>`，旁边是头像。
nonisolated enum LoggedInHomeParser {
    struct Result: Equatable, Sendable {
        let userID: Int
        let avatarURL: URL?
    }

    /// 未登录时返回空。
    static func parse(_ html: String) throws -> Result? {
        try HTML.parsing("home") {
            let document = try HTML.document(html, page: "home")
            guard let link = try document.select("a.dropdown-item[href*=/u/]").first(),
                  let userID = userID(fromHref: try link.attr("href")) else {
                return nil
            }
            return Result(userID: userID, avatarURL: HTML.imageURL(try document.select("#dropdownMenu2 img").first()))
        }
    }

    static func userID(fromHref href: String) -> Int? {
        guard let range = href.range(of: "/u/") else { return nil }
        return Int(href[range.upperBound...].prefix { $0.isNumber })
    }
}

/// 用户的已购专辑页 `/u/<id>/music/?page=<n>`。
/// 这个页面不登录也能看；以本人身份登录时，页面脚本里多一行 `var token = '<40 位十六进制>'`。
nonisolated enum ProfileMusicPageParser {
    struct Result: Sendable {
        let nickname: String?
        let avatarURL: URL?
        /// 只有以本人身份登录时才有。
        let token: String?
        let purchases: Page<PurchasedDisc>
    }

    static func parse(_ html: String) throws -> Result {
        try HTML.parsing("purchases") {
            let document = try HTML.document(html, page: "purchases")
            guard let discs = try document.select("#discs").first() else {
                throw DizzyError.parsing("purchases")
            }

            // 页头：左列头像，右列 h1 昵称。
            let nickname = try document.select("h1").first()
            let avatar = try nickname?.parent()?.parent()?.select("img").first()

            let purchases = try discs.select("a[href*=/d/]:has(.album_cover)").array().compactMap { link -> PurchasedDisc? in
                guard let id = HTML.discID(fromHref: try link.attr("href")) else { return nil }
                let footer = try link.parent()?.parent()?.select(".card-footer").first()
                let title = try footer?.select("[onclick^=updateplayer]").first()?.attr("title")
                let label = try footer?.select("h4 a[href*=/l/]").first()?.text()
                let date = try footer?.select("small.text-muted").first()?.text()
                let disc = DiscSummary(
                    id: id,
                    title: (title?.isEmpty == false ? title : nil) ?? id,
                    coverURL: HTML.imageURL(try link.select(".album_cover img").first()),
                    labelName: label.map(HTML.stripAt),
                    isHiRes: try !link.select("img[src*=hires]").isEmpty(),
                    isOwned: true
                )
                return PurchasedDisc(disc: disc, purchaseDate: date.map(purchaseDate))
            }

            return Result(
                nickname: try nickname?.text(),
                avatarURL: HTML.imageURL(avatar),
                token: token(in: html),
                purchases: Page(items: purchases, hasMore: HTML.hasNextPage(document))
            )
        }
    }

    static func token(in html: String) -> String? {
        html.firstMatch(of: #/var\s+token\s*=\s*['"]([0-9a-fA-F]{40})['"]/#).map { String($0.output.1) }
    }

    /// `购买于 2026-09-05` → `2026-09-05`。
    private static func purchaseDate(_ text: String) -> String {
        text.replacingOccurrences(of: "购买于", with: "").trimmingCharacters(in: .whitespaces)
    }
}
