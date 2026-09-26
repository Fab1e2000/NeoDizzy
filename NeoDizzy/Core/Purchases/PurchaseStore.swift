import Foundation

nonisolated struct PendingPurchase: Codable, Identifiable, Sendable {
    let attempt: PurchaseAttempt
    let title: String
    var id: UUID { attempt.id }
}

nonisolated enum PurchaseCheckState: Equatable {
    case waiting, checking, unconfirmed, confirmed
}

/// 每个账号保存一次待核验付款；不保存收银台地址和凭据。
@Observable
final class PurchaseStore {
    private var pendingByAccount: [Int: PendingPurchase] = [:]
    /// 成功提示只留在当前会话中，不随待核验记录持久化。
    private var completed: PendingPurchase?
    private(set) var state: PurchaseCheckState = .waiting
    private(set) var failure: String?
    private(set) var requiresLogin = false

    @ObservationIgnored private let accountID: () -> Int?
    @ObservationIgnored private let ownership: (String) async throws -> Bool
    @ObservationIgnored private let orders: (Int, PurchaseKind) async throws -> PaidOrderSnapshot
    @ObservationIgnored private let sleep: () async throws -> Void
    @ObservationIgnored private let defaults: UserDefaults
    @ObservationIgnored private var checkTask: Task<Void, Never>?
    @ObservationIgnored private var generation = 0
    private static let storageKey = "pendingPurchase.v2"
    private static let legacyStorageKey = "pendingPurchase.v1"

    init(
        accountID: @escaping () -> Int?,
        defaults: UserDefaults = .standard,
        ownership: @escaping (String) async throws -> Bool = {
            try await DizzyAPI.shared.discDetail(id: $0, fresh: true).summary.isOwned
        },
        orders: @escaping (Int, PurchaseKind) async throws -> PaidOrderSnapshot = {
            try await PurchaseStore.paidOrders(accountID: $0, kind: $1)
        },
        sleep: @escaping () async throws -> Void = { try await Task.sleep(for: .seconds(3)) }
    ) {
        self.accountID = accountID
        self.defaults = defaults
        self.ownership = ownership
        self.orders = orders
        self.sleep = sleep
        if let data = defaults.data(forKey: Self.storageKey),
           let records = try? JSONDecoder().decode([Int: PendingPurchase].self, from: data) {
            pendingByAccount = records.filter { $0.key == $0.value.attempt.accountID }
        }
        if let data = defaults.data(forKey: Self.legacyStorageKey),
           let legacy = try? JSONDecoder().decode(PendingPurchase.self, from: data) {
            if pendingByAccount[legacy.attempt.accountID] == nil {
                pendingByAccount[legacy.attempt.accountID] = legacy
            }
            try? persist(pendingByAccount)
        }
    }

    var current: PendingPurchase? {
        guard let accountID = accountID() else { return nil }
        return pendingByAccount[accountID]
            ?? (completed?.attempt.accountID == accountID ? completed : nil)
    }

    func begin(_ purchase: PendingPurchase) throws {
        let accountID = purchase.attempt.accountID
        guard accountID == self.accountID() else { throw DizzyError.sessionExpired }
        guard pendingByAccount[accountID] == nil else { throw PurchaseFlowError.pendingPayment }
        var updated = pendingByAccount
        updated[accountID] = purchase
        try persist(updated)
        pause()
        pendingByAccount = updated
        completed = nil
        state = .waiting
        failure = nil
        requiresLogin = false
    }

    func forget() {
        pause()
        if let accountID = accountID() {
            pendingByAccount[accountID] = nil
            if completed?.attempt.accountID == accountID { completed = nil }
            try? persist(pendingByAccount)
        }
        state = .waiting
        failure = nil
        requiresLogin = false
    }

    func accountDidChange() {
        pause()
        completed = nil
        state = .waiting
        failure = nil
        requiresLogin = false
    }

    /// 离开前台时停止轮询；账号切换或新任务会让在途结果失效。
    func pause() {
        generation += 1
        checkTask?.cancel()
        checkTask = nil
        if state == .checking { state = .waiting }
    }

    func check() async {
        guard let pending = current, state != .confirmed else { return }
        if let checkTask {
            await checkTask.value
            return
        }
        let requestGeneration = generation
        state = .checking
        failure = nil
        requiresLogin = false
        let task = Task { await poll(pending, generation: requestGeneration) }
        checkTask = task
        await task.value
        if requestGeneration == generation {
            checkTask = nil
            if state == .checking { state = .waiting }
        }
    }

    private func poll(_ purchase: PendingPurchase, generation requestGeneration: Int) async {
        for index in 0..<6 {
            guard isCurrent(purchase, generation: requestGeneration) else { return }
            var owned: Bool?
            var paid: PaidOrderSnapshot?
            do {
                if purchase.attempt.kind == .purchase {
                    owned = try await ownership(purchase.attempt.discID)
                } else {
                    paid = try await orders(purchase.attempt.accountID, purchase.attempt.kind)
                }
            } catch is CancellationError {
                return
            } catch {
                guard isCurrent(purchase, generation: requestGeneration) else { return }
                failure = error.localizedDescription
                if error as? DizzyError == .sessionExpired || error as? DizzyError == .notLoggedIn {
                    requiresLogin = true
                    state = .unconfirmed
                    return
                }
            }
            guard isCurrent(purchase, generation: requestGeneration) else { return }
            let result = PurchaseConfirmation.evaluate(purchase.attempt, accountID: accountID(), isOwned: owned, paidOrders: paid)
            if case .confirmed = result {
                state = .confirmed
                failure = nil
                // 核验成功即不再持久化；当前面板保留成功提示。
                pendingByAccount[purchase.attempt.accountID] = nil
                completed = purchase
                try? persist(pendingByAccount)
                NotificationCenter.default.post(name: .dizzyPurchaseDidComplete, object: purchase.attempt.discID)
                return
            }
            if index < 5 {
                do { try await sleep() } catch { return }
            }
        }
        guard isCurrent(purchase, generation: requestGeneration) else { return }
        state = .unconfirmed
    }

    private func isCurrent(_ purchase: PendingPurchase, generation requestGeneration: Int) -> Bool {
        !Task.isCancelled && generation == requestGeneration && current?.id == purchase.id
    }

    private func persist(_ records: [Int: PendingPurchase]) throws {
        if records.isEmpty {
            defaults.removeObject(forKey: Self.storageKey)
        } else {
            defaults.set(try JSONEncoder().encode(records), forKey: Self.storageKey)
        }
        defaults.removeObject(forKey: Self.legacyStorageKey)
    }

    static func paidOrders(accountID: Int, kind: PurchaseKind) async throws -> PaidOrderSnapshot {
        let path = kind == .boost ? "/albums/purchases/boost/" : "/albums/purchases/"
        let html = try await DizzyHTTPClient.shared.html(path: path, cachePolicy: .reloadIgnoringLocalCacheData)
        return try PaidOrdersParser.parse(html, accountID: accountID, kind: kind)
    }
}

nonisolated enum PurchaseFlowError: LocalizedError {
    case pendingPayment, offerChanged
    var errorDescription: String? {
        switch self {
        case .pendingPayment: "请先核验上一笔付款，或停止跟踪后再发起新的付款。"
        case .offerChanged: "购买状态或价格已更新，请确认最新金额后再次继续。"
        }
    }
}

nonisolated extension Notification.Name {
    static let dizzyPurchaseDidComplete = Notification.Name("NeoDizzy.purchaseDidComplete")
    static let dizzyPaymentReturned = Notification.Name("NeoDizzy.paymentReturned")
}
