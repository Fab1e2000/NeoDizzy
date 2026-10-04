import Foundation

nonisolated struct CheckoutSession: Identifiable {
    let id = UUID()
    let url: URL
    let credentials: DizzyCredentials.Snapshot
}

@Observable
final class PurchaseSheetModel {
    private(set) var offer: PurchaseOffer?
    private(set) var isLoading = false
    private(set) var isPreparing = false
    private(set) var requiresLogin = false
    var amountText = ""
    var comment = ""
    var failure: String?
    var checkout: CheckoutSession?
    private var generation = 0

    func load(discID: String, account: AccountStore) async {
        guard !isLoading, account.isLoggedIn, !account.isSessionExpired else { return }
        generation += 1
        let requestGeneration = generation
        let userID = account.account?.userID
        isLoading = true
        requiresLogin = false
        failure = nil
        defer { if generation == requestGeneration { isLoading = false } }
        do {
            let detail = try await DizzyAPI.shared.discDetail(id: discID, fresh: true)
            let result = try await DizzyPages.shared.purchaseOffer(discID: discID, isOwned: detail.summary.isOwned)
            try Task.checkCancellation()
            guard generation == requestGeneration, userID == account.account?.userID, !account.isSessionExpired else { return }
            offer = result
            amountText = result.initialAmount.text
        } catch is CancellationError {
        } catch {
            guard generation == requestGeneration else { return }
            failure = error.localizedDescription
            requiresLogin = error as? DizzyError == .notLoggedIn || error as? DizzyError == .sessionExpired
        }
    }

    func prepare(summary: DiscSummary, account: AccountStore, purchases: PurchaseStore) async {
        guard !isPreparing, let offer, let userID = account.account?.userID, !account.isSessionExpired else { return }
        isPreparing = true
        failure = nil
        let requestGeneration = generation
        defer { if generation == requestGeneration { isPreparing = false } }
        do {
            let amount = try offer.validate(amountText: amountText, comment: comment)
            // 点击付款后再核对价格和当前账号的所有权。下单地址只交给用户可见的收银台加载。
            let detail = try await DizzyAPI.shared.discDetail(id: summary.id, fresh: true)
            let fresh = try await DizzyPages.shared.purchaseOffer(discID: summary.id, isOwned: detail.summary.isOwned)
            guard generation == requestGeneration, userID == account.account?.userID, !account.isSessionExpired else { throw CancellationError() }
            self.offer = fresh
            guard fresh.kind == offer.kind, fresh.minimum == offer.minimum, fresh.basePrice == offer.basePrice else {
                amountText = fresh.initialAmount.text
                throw PurchaseFlowError.offerChanged
            }
            let url = try fresh.checkoutURL(amount: amount, comment: comment)
            // BOOST 必须保留付款前的已付订单基线；首次购买以拥有权限确认，不依赖订单页面。
            let baseline = fresh.kind == .boost ? try await PurchaseStore.paidOrders(accountID: userID, kind: .boost) : nil
            try Task.checkCancellation()
            guard generation == requestGeneration, userID == account.account?.userID, !account.isSessionExpired else { throw CancellationError() }
            let attempt = PurchaseAttempt(accountID: userID, discID: summary.id, kind: fresh.kind, amount: amount,
                                          wasOwned: detail.summary.isOwned, baseline: baseline)
            try purchases.begin(PendingPurchase(attempt: attempt, title: summary.title))
            checkout = CheckoutSession(url: url, credentials: DizzyHTTPClient.shared.credentials.snapshot)
        } catch is CancellationError {
        } catch {
            guard generation == requestGeneration else { return }
            failure = error.localizedDescription
            requiresLogin = error as? DizzyError == .notLoggedIn || error as? DizzyError == .sessionExpired
        }
    }

    func reset() {
        generation += 1
        checkout = nil
        offer = nil
        failure = nil
        isLoading = false
        isPreparing = false
        requiresLogin = false
        comment = ""
    }
}
