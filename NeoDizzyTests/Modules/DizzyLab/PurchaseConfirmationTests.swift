import Foundation
import Testing
@testable import NeoDizzy

struct PurchaseConfirmationTests {
    private let accountID = 123
    private let startedAt = Date(timeIntervalSince1970: 1_000.25)
    private var amount: PurchaseAmount { PurchaseAmount(cents: 1_000)! }

    private func snapshot(_ orders: [PaidOrder] = [], kind: PurchaseKind = .boost,
                          accountID: Int = 123, hasMore: Bool = false, at: Date? = nil) -> PaidOrderSnapshot {
        PaidOrderSnapshot(accountID: accountID, kind: kind, orderIDs: Set(orders.map(\.id)),
                          orders: orders, hasMore: hasMore, fetchedAt: at ?? startedAt.addingTimeInterval(-1))
    }

    private func attempt(kind: PurchaseKind = .boost, owned: Bool = true,
                         baseline: PaidOrderSnapshot? = nil) -> PurchaseAttempt {
        PurchaseAttempt(accountID: accountID, discID: "test-album", kind: kind, amount: amount,
                        wasOwned: owned, baseline: baseline, startedAt: startedAt)
    }

    private func order(id: String = "new", discID: String = "test-album", kind: PurchaseKind? = .boost,
                       amount: PurchaseAmount? = nil, at: Date? = nil) -> PaidOrder {
        PaidOrder(id: id, discID: discID, kind: kind, amount: amount ?? self.amount, createdAt: at)
    }

    @Test func priorOwnershipNeverConfirmsBoost() {
        #expect(PurchaseConfirmation.evaluate(attempt(), accountID: accountID,
                                             isOwned: true, paidOrders: nil) == .pending)
        #expect(PurchaseConfirmation.evaluate(attempt(baseline: snapshot()), accountID: accountID,
                                             isOwned: true, paidOrders: snapshot(at: startedAt)) == .pending)
    }

    @Test func onlyOwnershipTransitionConfirmsInitialPurchase() {
        let fresh = attempt(kind: .purchase, owned: false)
        #expect(PurchaseConfirmation.evaluate(fresh, accountID: accountID,
                                             isOwned: true, paidOrders: nil) == .confirmed(.newlyOwned))
        #expect(PurchaseConfirmation.evaluate(fresh, accountID: accountID,
                                             isOwned: false, paidOrders: nil) == .pending)
        #expect(PurchaseConfirmation.evaluate(attempt(kind: .purchase), accountID: accountID,
                                             isOwned: true, paidOrders: nil) == .pending)
    }

    @Test func networkFailureOrCancelledEvidenceDoesNotConfirmAnything() {
        // 调用方网络错误或已取消请求没有产生可用证据，不能用之前的 owned=true 顶替。
        #expect(PurchaseConfirmation.evaluate(attempt(baseline: snapshot()), accountID: accountID,
                                             isOwned: nil, paidOrders: nil) == .pending)
        #expect(PurchaseConfirmation.evaluate(attempt(kind: .purchase, owned: false), accountID: accountID,
                                             isOwned: nil, paidOrders: nil) == .pending)
    }

    @Test func paidOrderRequiresKnownBaselineAndExactProductTypeAmount() {
        let paid = snapshot([order(at: startedAt)], at: startedAt.addingTimeInterval(1))
        #expect(PurchaseConfirmation.evaluate(attempt(), accountID: accountID,
                                             isOwned: true, paidOrders: paid) == .pending)
        let before = snapshot()
        #expect(PurchaseConfirmation.evaluate(attempt(baseline: before), accountID: accountID,
                                             isOwned: true, paidOrders: paid) == .confirmed(.paidOrder("new")))
        for mismatch in [order(discID: "another"), order(kind: .purchase), order(kind: nil),
                         order(amount: PurchaseAmount(cents: 1_001)!)] {
            #expect(PurchaseConfirmation.evaluate(attempt(baseline: before), accountID: accountID,
                isOwned: true, paidOrders: snapshot([mismatch], at: startedAt)) == .pending)
        }
    }

    @Test func existingOrderAndWrongTabCannotConfirmBoost() {
        let paid = order()
        #expect(PurchaseConfirmation.evaluate(attempt(baseline: snapshot([paid])), accountID: accountID,
            isOwned: true, paidOrders: snapshot([paid], at: startedAt)) == .pending)
        #expect(PurchaseConfirmation.evaluate(attempt(baseline: snapshot(kind: .purchase)), accountID: accountID,
            isOwned: true, paidOrders: snapshot([paid], at: startedAt)) == .pending)
        #expect(PurchaseConfirmation.evaluate(attempt(baseline: snapshot()), accountID: accountID,
            isOwned: true, paidOrders: snapshot([paid], kind: .purchase, at: startedAt)) == .pending)
    }

    @Test func accountChangeRejectsAllEvidenceIncludingNewOwnership() {
        let fresh = attempt(kind: .purchase, owned: false)
        for current in [nil, 999] as [Int?] {
            #expect(PurchaseConfirmation.evaluate(fresh, accountID: current,
                                                 isOwned: true, paidOrders: nil) == .accountChanged)
        }
        let paid = snapshot([order()], accountID: 999, at: startedAt)
        #expect(PurchaseConfirmation.evaluate(attempt(baseline: snapshot()), accountID: accountID,
                                             isOwned: true, paidOrders: paid) == .pending)
        #expect(PurchaseConfirmation.evaluate(attempt(baseline: snapshot(accountID: 999)), accountID: accountID,
            isOwned: true, paidOrders: snapshot([order()], at: startedAt)) == .pending)
    }

    @Test func staleResponseOrFutureBaselineCannotConfirm() {
        #expect(PurchaseConfirmation.evaluate(attempt(baseline: snapshot()), accountID: accountID,
            isOwned: true, paidOrders: snapshot([order()])) == .pending)
        #expect(PurchaseConfirmation.evaluate(attempt(baseline: snapshot(at: startedAt.addingTimeInterval(1))),
            accountID: accountID, isOwned: true,
            paidOrders: snapshot([order()], at: startedAt.addingTimeInterval(2))) == .pending)
    }

    @Test func paginatedBaselineNeedsRecentOrderTimestamp() {
        let pending = attempt(baseline: snapshot(hasMore: true))
        for date in [nil, startedAt.addingTimeInterval(-100), startedAt.addingTimeInterval(100)] as [Date?] {
            #expect(PurchaseConfirmation.evaluate(pending, accountID: accountID, isOwned: true,
                paidOrders: snapshot([order(at: date)], at: startedAt.addingTimeInterval(2))) == .pending)
        }
        // 订单号精确到秒，创建时间允许和发起时间同一秒。
        let sameSecond = Date(timeIntervalSince1970: 1_000)
        #expect(PurchaseConfirmation.evaluate(pending, accountID: accountID, isOwned: true,
            paidOrders: snapshot([order(at: sameSecond)], at: startedAt.addingTimeInterval(2)))
            == .confirmed(.paidOrder("new")))
    }

    @Test func apparentlyCompleteBaselineCannotReviveAnOlderOmittedOrder() {
        let pending = attempt(baseline: snapshot())
        for date in [nil, startedAt.addingTimeInterval(-100)] as [Date?] {
            #expect(PurchaseConfirmation.evaluate(pending, accountID: accountID, isOwned: true,
                paidOrders: snapshot([order(at: date)], at: startedAt.addingTimeInterval(2))) == .pending)
        }
    }

    @Test func capturedOrderIDMustMatchExactly() {
        let pending = attempt(baseline: snapshot(hasMore: true))
        let current = snapshot([order()], at: startedAt)
        #expect(PurchaseConfirmation.evaluate(pending, accountID: accountID, isOwned: true,
                                             paidOrders: current, expectedOrderID: "other") == .pending)
        #expect(PurchaseConfirmation.evaluate(pending, accountID: accountID, isOwned: true,
            paidOrders: current, expectedOrderID: "new") == .confirmed(.paidOrder("new")))
    }

    @Test func pendingAttemptPersistsOnlyConfirmationMetadata() throws {
        let original = attempt(baseline: snapshot([order()]))
        let data = try JSONEncoder().encode(original)
        #expect(try JSONDecoder().decode(PurchaseAttempt.self, from: data) == original)
        let json = String(decoding: data, as: UTF8.self)
        #expect(!json.contains("checkout"))
        #expect(!json.contains("token"))
        #expect(!json.contains("cookie"))
    }

    @Test func parsesObservedPaidOrderCardWithSyntheticValues() throws {
        let parsed = try PaidOrdersParser.parse(Self.page(), accountID: accountID, kind: .purchase, fetchedAt: startedAt)
        #expect(parsed.accountID == accountID)
        #expect(parsed.kind == .purchase)
        #expect(parsed.orderIDs == ["dizz_123_test-album_2026-09-26-09-55-11_abcd"])
        #expect(!parsed.hasMore)
        let paid = try #require(parsed.orders.first)
        #expect(paid.discID == "test-album")
        #expect(paid.amount == amount)
        #expect(paid.kind == .purchase)
        #expect(paid.createdAt == ISO8601DateFormatter().date(from: "2026-09-26T01:55:11Z"))
    }

    @Test func separatesBoostTabAndRecognizesEmptyOrderList() throws {
        let parsed = try PaidOrdersParser.parse(Self.page(kind: .boost), accountID: accountID, kind: .boost)
        #expect(parsed.orders.first?.kind == .boost)
        #expect(throws: DizzyError.parsing("paid-orders")) {
            try PaidOrdersParser.parse(Self.page(), accountID: accountID, kind: .boost)
        }
        let empty = try PaidOrdersParser.parse(Self.page(kind: .boost, cards: ""), accountID: accountID, kind: .boost)
        #expect(empty.orderIDs.isEmpty)
        #expect(empty.orders.isEmpty)
    }

    @Test func observedBoostOrderFormatConfirmsMatchingPendingSupport() throws {
        let orderTime = try #require(ISO8601DateFormatter().date(from: "2026-09-26T01:55:11Z"))
        let startedAt = orderTime.addingTimeInterval(0.405)
        let baseline = try PaidOrdersParser.parse(Self.page(kind: .boost, cards: ""),
            accountID: accountID, kind: .boost, fetchedAt: startedAt.addingTimeInterval(-1))
        let current = try PaidOrdersParser.parse(Self.page(kind: .boost), accountID: accountID,
            kind: .boost, fetchedAt: startedAt.addingTimeInterval(30))
        let pending = PurchaseAttempt(accountID: accountID, discID: "test-album", kind: .boost,
            amount: amount, wasOwned: true, baseline: baseline, startedAt: startedAt)
        let id = "dizz_boost_123_test-album_2026-09-26-09-55-11_abcd"
        #expect(current.orderIDs == [id])
        #expect(current.orders.first?.createdAt == orderTime)
        #expect(PurchaseConfirmation.evaluate(pending, accountID: accountID,
            isOwned: true, paidOrders: current) == .confirmed(.paidOrder(id)))
    }

    @Test func orderNumberKindMustMatchPageKind() throws {
        let boostWithPurchaseID = Self.page(kind: .boost).replacingOccurrences(of: "dizz_boost_", with: "dizz_")
        let purchaseWithBoostID = Self.page().replacingOccurrences(of: "dizz_123_", with: "dizz_boost_123_")
        for (html, kind) in [(boostWithPurchaseID, PurchaseKind.boost), (purchaseWithBoostID, .purchase)] {
            let parsed = try PaidOrdersParser.parse(html, accountID: accountID, kind: kind)
            #expect(parsed.orderIDs.count == 1)
            #expect(parsed.orders.first?.createdAt == nil)
        }
    }

    @Test func malformedOrForeignPaidOrderPageCannotYieldSuccessEvidence() {
        for html in [Self.page().replacingOccurrences(of: "订单号", with: "参考编号"),
                     Self.page().replacingOccurrences(of: "dizz_123_", with: "unexpected_123_"),
                     "<html><title>出错了！</title></html>", "<html></html>"] {
            #expect(throws: (any Error).self) {
                try PaidOrdersParser.parse(html, accountID: accountID, kind: .purchase)
            }
        }
        #expect(throws: DizzyError.sessionExpired) {
            try PaidOrdersParser.parse(Self.page(), accountID: 999, kind: .purchase)
        }
        #expect(throws: DizzyError.sessionExpired) {
            try PaidOrdersParser.parse("<form method='post'><input name='password'></form>",
                                       accountID: accountID, kind: .purchase)
        }
    }

    @Test func historicalCartAndUnrecognizedOrderIDsRemainInBaselineWithoutConfirmationEvidence() throws {
        for id in ["dizz_cart_123_2026-09-26-09-55-11_abcd_test-album",
                   "dizz_999_test-album_2026-09-26-09-55-11_abcd"] {
            let html = Self.page().replacingOccurrences(
                of: "dizz_123_test-album_2026-09-26-09-55-11_abcd", with: id
            )
            let parsed = try PaidOrdersParser.parse(html, accountID: accountID, kind: .purchase)
            #expect(parsed.orderIDs.contains(id))
            #expect(parsed.orders.first?.createdAt == nil)
            let pending = attempt(kind: .purchase, owned: false, baseline: snapshot(kind: .purchase))
            #expect(PurchaseConfirmation.evaluate(pending, accountID: accountID,
                isOwned: false, paidOrders: parsed) == .pending)
        }
    }

    @Test func unknownPriceCannotBeMistakenForZeroAndPaginationIsDetected() throws {
        let html = Self.page().replacingOccurrences(of: "价格 10.0元", with: "价格 待核对")
        #expect(try PaidOrdersParser.parse(html, accountID: accountID, kind: .purchase).orders.first?.amount == nil)
        let paginated = Self.page().replacingOccurrences(of: "</body>", with:
            "<nav><ul class='pagination'><li><a href='?page=2'>2</a></li></ul></nav></body>")
        #expect(try PaidOrdersParser.parse(paginated, accountID: accountID, kind: .purchase).hasMore)
    }

    /// 卡片结构来自只读真机页面；账号、订单、作品、金额均为虚构数据。
    private static func page(kind: PurchaseKind = .purchase, cards: String? = nil) -> String {
        let card = cards ?? """
        <div class="card"><div class="card-body">
        <a href="/albums/d/test-album"><img data-src="https://cdn.dizzylab.net/media/cover/example.jpg!cover"></a>
        <h1 class="text-truncate">示例专辑</h1><h3>示例社团</h3>
        <h3>价格 10.0元， 购买于 2026年9月26日 09:55</h3>
        <h3 class="text-warning">订单号 dizz_\(kind == .boost ? "boost_" : "")123_test-album_2026-09-26-09-55-11_abcd</h3>
        </div></div>
        """
        return """
        <html><head><title>示例用户的全部订单 - dizzylab</title></head><body>
        <a class="dropdown-item" href="/u/123">个人信息</a>
        <div class="container"><div class="row"><div class="col-lg-7">
        <nav class="nav nav-pills" role="tablist">
        <a class="nav-item nav-link \(kind == .purchase ? "active" : "")" href="/albums/purchases/">数字商品</a>
        <a class="nav-item nav-link \(kind == .boost ? "active" : "")" href="/albums/purchases/boost/">BOOST</a>
        </nav>
        \(card)
        <nav><ul class="pagination"><li class="page-item active"><span>1</span></li></ul></nav>
        </div></div></div></body></html>
        """
    }
}
