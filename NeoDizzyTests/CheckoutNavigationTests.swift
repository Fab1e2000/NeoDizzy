import Foundation
import Testing
@testable import NeoDizzy

struct CheckoutNavigationTests {
    @Test(arguments: [
        "https://www.dizzylab.net/albums/checkout_alipay/?id=sample&type=dig",
        "https://www.dizzylab.net/d/sample/",
        "https://mclient.alipay.com/h5pay/landing",
        "https://excashier.alipay.com/standard/auth.htm",
        "https://alipay.com/",
    ])
    func siteAndAlipayHTTPSStayInWebView(_ string: String) throws {
        #expect(CheckoutNavigationPolicy.decision(for: try #require(URL(string: string))) == .allow)
    }

    @Test(arguments: [
        "https://alipay.com.example.com/", "https://fakealipay.com/",
        "https://www.dizzylab.net.example.com/", "https://cdn.dizzylab.net/",
        "https://www.dizzylab.net@evil.example/", "https://user@www.dizzylab.net/",
        "https://www.dizzylab.net:8080/", "http://mclient.alipay.com/",
        "http://www.dizzylab.net/", "file:///tmp/payment.html", "javascript:alert(1)",
        "tel:123", "weixin://pay", "https://example.com/", "about:blank",
    ])
    func otherOriginsAndSchemesAreBlocked(_ string: String) throws {
        #expect(CheckoutNavigationPolicy.decision(for: try #require(URL(string: string))) == .block)
    }

    @Test(arguments: ["alipays://platformapi/startapp?appId=20000067", "alipay://platformapi/startapp"])
    func onlyAlipaySchemesOpenAnotherApp(_ string: String) throws {
        #expect(CheckoutNavigationPolicy.decision(for: try #require(URL(string: string))) == .openAlipay)
    }

    @Test func blankFramesArePermittedWithoutReplacingCheckout() throws {
        let blank = try #require(URL(string: "about:blank"))
        #expect(CheckoutNavigationPolicy.decision(for: blank, isMainFrame: false) == .allow)
        #expect(CheckoutNavigationPolicy.decision(for: blank, isMainFrame: true) == .block)
    }

    @Test func returningToSiteIsOnlyARecheckSignal() throws {
        let checkout = try #require(URL(string: "https://www.dizzylab.net/albums/checkout_alipay/?id=sample"))
        let returned = try #require(URL(string: "https://www.dizzylab.net/d/sample/?payment=success"))
        let lookalike = try #require(URL(string: "https://www.dizzylab.net.evil.example/d/sample/"))
        #expect(CheckoutNavigationPolicy.isCheckoutURL(checkout))
        #expect(!CheckoutNavigationPolicy.isSiteReturn(checkout))
        #expect(CheckoutNavigationPolicy.isSiteReturn(returned))
        #expect(!CheckoutNavigationPolicy.isSiteReturn(lookalike))
        #expect(!CheckoutNavigationPolicy.isCheckoutURL(returned))
    }

    @Test func cookieSnapshotIncludesOnlyLiveSiteCookiesAndNeverAPIToken() throws {
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        let snapshot = DizzyCredentials.Snapshot(cookies: [
            StoredCookie(name: "sessionid", value: "session", expires: nil),
            StoredCookie(name: "csrftoken", value: "csrf", expires: now.addingTimeInterval(300)),
            StoredCookie(name: "expired", value: "old", expires: now),
            StoredCookie(name: "empty", value: "", expires: nil),
        ], token: "must-not-leave-native-api")
        let cookies = CheckoutNavigationPolicy.cookies(from: snapshot, now: now)
        #expect(Set(cookies.map(\.name)) == ["sessionid", "csrftoken"])
        #expect(cookies.allSatisfy { $0.domain == "www.dizzylab.net" && $0.path == "/" && $0.isSecure })
        #expect(cookies.allSatisfy { $0.value != snapshot.token })
    }
}
