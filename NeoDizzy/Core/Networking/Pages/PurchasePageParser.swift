import Foundation
import SwiftSoup

nonisolated enum PurchasePageParser {
    static func parse(_ html: String, discID: String, isOwned: Bool) throws -> PurchaseOffer {
        let document = try HTML.document(html, page: "购买价格")
        if try document.select("#yourprice").isEmpty(), try !document.select("input[name=password]").isEmpty() {
            throw DizzyError.notLoggedIn
        }
        // Redeem-only pages still embed valid-looking checkout forms. Their visible action,
        // not the hidden form, establishes whether a new digital purchase is available.
        if !isOwned {
            let hasPurchaseAction = try document.select("a.btn, button.btn").array().contains { element in
                let text = try element.text()
                return text.contains("现在购买") || text.contains("预购") || text == "免费"
            }
            guard hasPurchaseAction else { throw PurchaseFailure.unavailable }
        }
        // Physical products use type=dig too, but require shipping fields not supported by M4.
        guard try document.select("#ship_name, #ship_phone, #ship_add").isEmpty() else {
            throw PurchaseFailure.unavailable
        }
        let kind: PurchaseKind = isOwned ? .boost : .purchase
        let suffix = isOwned ? "_boost" : ""
        let modalID = isOwned ? "modalcheckoutboost" : "modalcheckout"
        guard let purchaseModal = try document.select("#modalcheckout").first(),
              let modal = try document.select("#\(modalID)").first(),
              let input = try modal.select("#yourprice\(suffix)").first(),
              let minimum = PurchaseAmount(text: try input.attr("min")),
              let initial = PurchaseAmount(text: try input.attr("value")), initial >= minimum,
              let comment = try modal.select("#ordercommit\(suffix)").first(),
              let limit = Int(try comment.attr("maxlength")), limit == 100 else {
            throw DizzyError.parsing("购买价格")
        }
        let priceScript = try purchaseModal.select("script").array().map { $0.data() }.joined(separator: "\n")
        guard let match = priceScript.firstMatch(of: #/\bdiscprice\s*=\s*([0-9]+(?:\.[0-9]+)?)\.toFixed\(2\)/#),
              let basePrice = PurchaseAmount(text: String(match.1)) else {
            throw DizzyError.parsing("购买价格")
        }
        let scripts = try modal.select("script").array().map { $0.data() }.joined(separator: "\n")
        guard scripts.matches(of: #/var\s+checkoutref\s*=\s*['"]([^'"]+)['"]/#).contains(where: { match in
            validCheckoutPrefix(String(match.1), discID: discID, kind: kind)
        }) else { throw DizzyError.parsing("购买价格") }
        let requiresLogin = try document.select("a[href]").array().contains { link in
            let href = try link.attr("href")
            guard let url = URL(string: href, relativeTo: DizzyURL.site)?.absoluteURL else { return false }
            return url.host == DizzyURL.site.host && ["/albums/login", "/albums/login/"].contains(url.path(percentEncoded: false))
        }
        return PurchaseOffer(discID: discID, kind: kind, minimum: minimum, initialAmount: initial,
                             basePrice: basePrice, commentLimit: limit, requiresLogin: requiresLogin)
    }

    private static func validCheckoutPrefix(_ value: String, discID: String, kind: PurchaseKind) -> Bool {
        guard let url = URL(string: value, relativeTo: DizzyURL.site)?.absoluteURL,
              url.scheme == "https", url.host == DizzyURL.site.host,
              url.port == nil || url.port == 443, url.user == nil, url.password == nil,
              url.path(percentEncoded: false) == "/albums/checkout_alipay/", url.fragment == nil,
              let items = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems,
              items.count == 4 else { return false }
        let expected = ["id": discID, "q": "1", "type": kind.rawValue, "price": ""]
        return Set(items.map(\.name)) == Set(expected.keys) && items.allSatisfy { expected[$0.name] == $0.value }
    }
}
