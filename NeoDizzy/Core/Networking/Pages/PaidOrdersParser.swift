import Foundation
import SwiftSoup

/// 全部订单的数字商品、BOOST 两个页签只展示已付款订单。
/// 此处只接受已观察到的卡片结构；页面改版时保留「待核验」，不猜测付款成功。
nonisolated enum PaidOrdersParser {
    static func parse(
        _ html: String,
        accountID: Int,
        kind: PurchaseKind,
        fetchedAt: Date = Date()
    ) throws -> PaidOrderSnapshot {
        if LoginPageParser.isLoginForm(html) { throw DizzyError.sessionExpired }
        return try HTML.parsing("paid-orders") {
            let document = try HTML.document(html, page: "paid-orders")
            guard let loggedIn = try LoggedInHomeParser.parse(html), loggedIn.userID == accountID else {
                throw DizzyError.sessionExpired
            }
            let expectedPath = kind == .boost ? "/albums/purchases/boost/" : "/albums/purchases/"
            guard let tab = try document.select("nav[role=tablist] a.active[href]").first(),
                  siteURL(try tab.attr("href"))?.path(percentEncoded: false) == expectedPath,
                  let container = tab.parent()?.parent() else {
                throw DizzyError.parsing("paid-orders")
            }

            var ids = Set<String>()
            var orders = [PaidOrder]()
            for card in try container.select(".card > .card-body").array() {
                let orderLabels = try card.select("h3.text-warning").array().map { try $0.text() }
                guard orderLabels.count == 1,
                      let match = orderLabels[0].wholeMatch(of: #/订单号\s+(\S+)/#) else {
                    throw DizzyError.parsing("paid-orders")
                }
                let id = String(match.output.1)
                // 历史购物车订单使用 dizz_cart_<账号>_...，与单张购买的编号结构不同。
                // 当前账号已由登录导航核实；未知编号格式仍计入基线，但不生成可确认付款的时间证据。
                guard id.hasPrefix("dizz_"), ids.insert(id).inserted else {
                    throw DizzyError.parsing("paid-orders")
                }

                let discIDs = try Set(card.select("a[href]").array().compactMap { link in
                    discID(try link.attr("href"))
                })
                // Pack 或将来新增的商品也必须计入基线，但不作为单张专辑的付款证据。
                guard discIDs.count == 1, let discID = discIDs.first else { continue }
                let headings = try card.select("h3").array().map { try $0.text() }
                let prices = headings.compactMap { heading -> PurchaseAmount? in
                    guard let price = heading.firstMatch(of: #/^价格\s+([0-9]+(?:\.[0-9]{1,2})?)元[，,]\s*购买于\s+/#) else {
                        return nil
                    }
                    return PurchaseAmount(text: String(price.output.1))
                }
                orders.append(PaidOrder(
                    id: id,
                    discID: discID,
                    kind: kind,
                    amount: prices.count == 1 ? prices.first : nil,
                    createdAt: creationDate(id, accountID: accountID, discID: discID, kind: kind)
                ))
            }

            // 除「下一页」外兼容网站页码按钮，避免遗漏旧页导致旧订单被误认为新增。
            let otherPage = try document.select(".pagination a[href]").array().contains { link in
                guard let url = siteURL(try link.attr("href")),
                      let page = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems?
                        .first(where: { $0.name == "page" })?.value.flatMap(Int.init) else { return false }
                return page > 1
            }
            return PaidOrderSnapshot(
                accountID: accountID,
                kind: kind,
                orderIDs: ids,
                orders: orders,
                hasMore: otherPage || HTML.hasNextPage(document),
                fetchedAt: fetchedAt
            )
        }
    }

    private static func siteURL(_ href: String) -> URL? {
        guard let url = URL(string: href, relativeTo: DizzyURL.site)?.absoluteURL,
              url.scheme == "https", url.host == DizzyURL.site.host,
              url.port == nil || url.port == 443, url.user == nil, url.password == nil else { return nil }
        return url
    }

    private static func discID(_ href: String) -> String? {
        guard let url = siteURL(href) else { return nil }
        let parts = url.pathComponents.filter { $0 != "/" }
        if parts.count == 3, parts[0] == "albums", parts[1] == "d" { return parts[2] }
        if parts.count == 2, parts[0] == "d" { return parts[1] }
        return nil
    }

    private static func creationDate(_ id: String, accountID: Int, discID: String, kind: PurchaseKind) -> Date? {
        // 网站的追加支持订单额外带 boost 段，必须和当前订单页签一致。
        let prefix = kind == .boost ? "dizz_boost_\(accountID)_\(discID)_" : "dizz_\(accountID)_\(discID)_"
        guard id.hasPrefix(prefix),
              let match = String(id.dropFirst(prefix.count)).wholeMatch(
                of: #/([0-9]{4}-[0-9]{2}-[0-9]{2}-[0-9]{2}-[0-9]{2}-[0-9]{2})_[A-Za-z0-9]+/#
              ) else { return nil }
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(identifier: "Asia/Shanghai")
        formatter.dateFormat = "yyyy-MM-dd-HH-mm-ss"
        formatter.isLenient = false
        return formatter.date(from: String(match.output.1))
    }
}
