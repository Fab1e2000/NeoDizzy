import Foundation

/// 付款前保存的事实。所有权只能证明首次购买，不能证明对已购作品的追加支持。
nonisolated struct PurchaseAttempt: Codable, Equatable, Identifiable, Sendable {
    let id: UUID
    let accountID: Int
    let discID: String
    let kind: PurchaseKind
    let amount: PurchaseAmount
    let wasOwned: Bool
    let baseline: PaidOrderSnapshot?
    let startedAt: Date

    init(id: UUID = UUID(), accountID: Int, discID: String, kind: PurchaseKind,
         amount: PurchaseAmount, wasOwned: Bool, baseline: PaidOrderSnapshot?, startedAt: Date = Date()) {
        self.id = id
        self.accountID = accountID
        self.discID = discID
        self.kind = kind
        self.amount = amount
        self.wasOwned = wasOwned
        self.baseline = baseline
        self.startedAt = startedAt
    }
}

/// 只保存核验所需的订单字段，不保存收银台地址、附言或付款凭据。
nonisolated struct PaidOrder: Codable, Equatable, Identifiable, Sendable {
    let id: String
    let discID: String
    let kind: PurchaseKind?
    let amount: PurchaseAmount?
    let createdAt: Date?
}

nonisolated struct PaidOrderSnapshot: Codable, Equatable, Sendable {
    let accountID: Int
    let kind: PurchaseKind
    /// 即使某个订单缺少可识别的类型或金额，也必须计入基线。
    let orderIDs: Set<String>
    let orders: [PaidOrder]
    let hasMore: Bool
    let fetchedAt: Date
}

nonisolated enum PurchaseConfirmationEvidence: Equatable, Sendable {
    case newlyOwned
    case paidOrder(String)
}

nonisolated enum PurchaseConfirmationResult: Equatable, Sendable {
    case confirmed(PurchaseConfirmationEvidence)
    case pending
    case accountChanged
}

nonisolated enum PurchaseConfirmation {
    /// 网络失败、未知 HTML 或仍未同步的结果均不能变成付款成功。
    /// 异步任务取消和 attempt.id 的一致性由调用方检查，再应用本方法返回的证据。
    static func evaluate(
        _ attempt: PurchaseAttempt,
        accountID: Int?,
        isOwned: Bool?,
        paidOrders: PaidOrderSnapshot?,
        expectedOrderID: String? = nil
    ) -> PurchaseConfirmationResult {
        guard accountID == attempt.accountID else { return .accountChanged }

        if attempt.kind == .purchase, !attempt.wasOwned, isOwned == true {
            return .confirmed(.newlyOwned)
        }

        guard let baseline = attempt.baseline,
              baseline.accountID == attempt.accountID,
              baseline.kind == attempt.kind,
              baseline.fetchedAt <= attempt.startedAt,
              let current = paidOrders,
              current.accountID == attempt.accountID,
              current.kind == attempt.kind,
              current.fetchedAt >= attempt.startedAt else { return .pending }

        let match = current.orders.first { order in
            guard current.orderIDs.contains(order.id),
                  !baseline.orderIDs.contains(order.id),
                  order.discID == attempt.discID,
                  order.kind == attempt.kind,
                  order.amount == attempt.amount else { return false }
            if let expectedOrderID {
                return order.id == expectedOrderID
            }
            // 分页或暂时不完整的页面可能遗漏旧订单。即使基线看起来完整，也要求创建时间新鲜。
            guard let createdAt = order.createdAt else { return false }
            let earliest = Date(timeIntervalSince1970: floor(attempt.startedAt.timeIntervalSince1970))
            return createdAt >= earliest && createdAt <= current.fetchedAt
        }
        return match.map { .confirmed(.paidOrder($0.id)) } ?? .pending
    }
}
