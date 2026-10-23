import Foundation
import Testing
@testable import NeoDizzy

struct PurchaseTests {
    @Test func parsesCurrentPurchaseSaleAndFreeOffers() throws {
        let regular = try PurchasePageParser.parse(Fixture.text("purchase-regular.html"), discID: "ALCD0001", isOwned: false)
        #expect(regular.kind == .purchase)
        #expect(regular.minimum.cents == 3800 && regular.initialAmount.cents == 3800)
        #expect(regular.basePrice.cents == 3800)
        #expect(regular.requiresLogin)
        let sale = try PurchasePageParser.parse(Fixture.text("purchase-sale.html"), discID: "KSEP-001", isOwned: false)
        #expect(sale.minimum.cents == 1800 && sale.basePrice.cents == 1800)
        #expect(sale.boostPercentage(amount: try #require(PurchaseAmount(text: "19"))) == 105)
        let free = try PurchasePageParser.parse(Fixture.text("purchase-free.html"), discID: "fx4", isOwned: false)
        #expect(free.minimum.cents == 0 && free.initialAmount.cents == 0)
        #expect(free.boostPercentage(amount: free.initialAmount) == nil)
        #expect(try free.validate(amountText: "0", comment: "").cents == 0)
    }

    @Test func ownedAlbumUsesAdditionalSupportForm() throws {
        let offer = try PurchasePageParser.parse(Fixture.text("purchase-owned.html"), discID: "ALCD0001", isOwned: true)
        #expect(offer.kind == .boost && !offer.requiresLogin)
        #expect(offer.minimum.cents == 100 && offer.initialAmount.cents == 1000)
        #expect(offer.basePrice.cents == 3800 && offer.commentLimit == 100)
        #expect(offer.boostPercentage(amount: offer.initialAmount) == nil)
        #expect(throws: PurchaseFailure.self) { try offer.validate(amountText: "0", comment: "") }
        let url = try offer.checkoutURL(amount: offer.initialAmount, comment: "")
        #expect(URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems?.first(where: { $0.name == "type" })?.value == "boost")
    }

    @Test func hiddenFormsDoNotEnableRedeemOnlyOrPhysicalPurchases() throws {
        #expect(throws: PurchaseFailure.self) {
            try PurchasePageParser.parse(Fixture.text("purchase-redeem.html"), discID: "ALCD0003", isOwned: false)
        }
        #expect(throws: PurchaseFailure.self) {
            try PurchasePageParser.parse(Fixture.text("purchase-physical.html"), discID: "obs-CD06BP", isOwned: false)
        }
        #expect(throws: PurchaseFailure.self) {
            try PurchasePageParser.parse(Fixture.text("purchase-physical.html"), discID: "obs-CD06BP", isOwned: true)
        }
    }

    @Test func rejectsLoginMalformedPriceWrongAlbumAndChangedCheckout() throws {
        #expect(throws: DizzyError.self) {
            try PurchasePageParser.parse(Fixture.text("purchase-login.html"), discID: "ALCD0001", isOwned: false)
        }
        let html = try Fixture.text("purchase-regular.html")
        for damaged in [
            html.replacingOccurrences(of: "min=\"38\"", with: "min=\"NaN\""),
            html.replacingOccurrences(of: "discprice=38.0", with: "discprice=unknown"),
            html.replacingOccurrences(of: "type=dig", with: "type=pack"),
            html.replacingOccurrences(of: "id=ALCD0001", with: "id=OTHER"),
            html.replacingOccurrences(of: "/albums/checkout_alipay/", with: "https://other.invalid/albums/checkout_alipay/"),
            html.replacingOccurrences(of: "maxlength=\"100\"", with: "maxlength=\"200\""),
        ] {
            #expect(throws: (any Error).self) { try PurchasePageParser.parse(damaged, discID: "ALCD0001", isOwned: false) }
        }
    }

    @Test(arguments: ["", "-1", "+1", "NaN", "Infinity", "1e2", "1,000", "0.001", "1.", ".5", "１", "1000000", "9999999999999999999999999999999999"])
    func rejectsInvalidOrOverpreciseAmounts(_ text: String) {
        #expect(PurchaseAmount(text: text) == nil)
    }

    @Test func exactAmountsIncrementsAndBounds() throws {
        let amount = try #require(PurchaseAmount(text: "00018.10"))
        #expect(amount.cents == 1810 && amount.text == "18.10")
        #expect(amount.decimal == Decimal(string: "18.10"))
        #expect(PurchaseAmount(text: " 0.01 ")?.cents == 1)
        #expect(PurchaseAmount(text: "0")?.text == "0")
        for increment in [1, 5, 10, 50] {
            #expect(amount.adding(yuan: increment)?.cents == 1810 + increment * 100)
        }
        #expect(PurchaseAmount(text: "999999.99")?.adding(yuan: 1) == nil)
        #expect(amount.adding(yuan: Int.max) == nil)
        #expect(amount.adding(yuan: -1) == nil)
        #expect(PurchaseAmount(cents: -1) == nil)
        let encoded = try JSONEncoder().encode(amount)
        #expect(try JSONDecoder().decode(PurchaseAmount.self, from: encoded) == amount)
        #expect(throws: DecodingError.self) { try JSONDecoder().decode(PurchaseAmount.self, from: Data("{\"cents\":-1}".utf8)) }
    }

    @Test func validatesMinimumAndWebsiteUTF16CommentLimit() throws {
        let offer = try PurchasePageParser.parse(Fixture.text("purchase-regular.html"), discID: "ALCD0001", isOwned: false)
        #expect(throws: PurchaseFailure.self) { try offer.validate(amountText: "37.99", comment: "") }
        #expect(try offer.validate(amountText: "38", comment: String(repeating: "字", count: 100)).cents == 3800)
        #expect(try offer.validate(amountText: "38", comment: String(repeating: "🎵", count: 50)).cents == 3800)
        #expect(throws: PurchaseFailure.self) { try offer.validate(amountText: "38", comment: String(repeating: "🎵", count: 51)) }
        #expect(throws: PurchaseFailure.self) { try offer.checkoutURL(amount: try #require(PurchaseAmount(text: "1")), comment: "") }
    }

    @Test func checkoutURLPreservesSpecialCharactersWithoutQueryInjection() throws {
        let amount = try #require(PurchaseAmount(text: "38.01"))
        let offer = PurchaseOffer(discID: "专辑&+/#=?", kind: .purchase, minimum: amount,
                                  initialAmount: amount, basePrice: amount, commentLimit: 100, requiresLogin: false)
        let comment = "谢谢 & price=1 + C++\n🎵 #?"
        let url = try offer.checkoutURL(amount: amount, comment: comment)
        let components = try #require(URLComponents(url: url, resolvingAgainstBaseURL: false))
        #expect(url.host == DizzyURL.site.host && url.path(percentEncoded: false) == "/albums/checkout_alipay/")
        #expect(url.fragment == nil && components.queryItems?.count == 5)
        #expect(components.queryItems?.first(where: { $0.name == "id" })?.value == offer.discID)
        #expect(components.queryItems?.first(where: { $0.name == "commit" })?.value == comment)
        #expect(components.queryItems?.first(where: { $0.name == "price" })?.value == "38.01")
        #expect(url.absoluteString.contains("%2B") && !url.absoluteString.contains("+"))
    }

    @Test func fetchesOfferWithoutCacheAndRejectsExpiredSession() async throws {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [PurchaseOfferProtocol.self]
        let credentials = DizzyCredentials()
        credentials.store(HTTPCookie.cookies(withResponseHeaderFields: ["Set-Cookie": "sessionid=test-session; Path=/"], for: DizzyURL.site))
        let pages = DizzyPages(client: DizzyHTTPClient(session: URLSession(configuration: configuration), credentials: credentials))
        let offer = try await pages.purchaseOffer(discID: "ALCD0001", isOwned: true)
        #expect(offer.kind == .boost)
        await #expect(throws: DizzyError.self) { try await pages.purchaseOffer(discID: "expired", isOwned: false) }
        await #expect(throws: DizzyError.self) { try await DizzyPages(client: DizzyHTTPClient(credentials: DizzyCredentials())).purchaseOffer(discID: "ALCD0001", isOwned: true) }
    }
}

nonisolated private final class PurchaseOfferProtocol: URLProtocol, @unchecked Sendable {
    override class func canInit(with request: URLRequest) -> Bool { request.url?.host == DizzyURL.site.host }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        guard request.cachePolicy == .reloadIgnoringLocalCacheData,
              request.value(forHTTPHeaderField: "Cookie")?.contains("sessionid=test-session") == true else {
            client?.urlProtocol(self, didFailWithError: URLError(.badServerResponse))
            return
        }
        Task { @MainActor in
            do {
                let expired = request.url?.path.contains("expired") == true
                let fixture = expired ? "purchase-regular.html" : "purchase-owned.html"
                let html = try Fixture.text(fixture).replacingOccurrences(of: "ALCD0001", with: expired ? "expired" : "ALCD0001")
                let response = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: "HTTP/1.1", headerFields: ["Content-Type": "text/html"])!
                client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
                client?.urlProtocol(self, didLoad: Data(html.utf8))
                client?.urlProtocolDidFinishLoading(self)
            } catch {
                client?.urlProtocol(self, didFailWithError: error)
            }
        }
    }
    override func stopLoading() { }
}
