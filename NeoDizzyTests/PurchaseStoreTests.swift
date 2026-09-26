import Foundation
import Testing
@testable import NeoDizzy

@MainActor
struct PurchaseStoreTests {
    private final class AccountContext {
        var id: Int? = 42
    }

    /// Deterministic suspension also models transports that finish after cancellation.
    private final class Signal<Value> {
        private var result: Value?
        private var continuations: [CheckedContinuation<Value, Never>] = []

        func value() async -> Value {
            if let result { return result }
            return await withCheckedContinuation { continuations.append($0) }
        }

        func send(_ value: Value) {
            result = value
            let waiting = continuations
            continuations.removeAll()
            waiting.forEach { $0.resume(returning: value) }
        }
    }

    private final class OwnershipGate {
        let entered = Signal<Bool>()
        let result = Signal<Bool>()
        var discIDs: [String] = []

        func fetch(_ discID: String) async -> Bool {
            discIDs.append(discID)
            entered.send(true)
            return await result.value()
        }
    }

    private func makeDefaults() throws -> (name: String, defaults: UserDefaults) {
        let name = "NeoDizzy.PurchaseStoreTests.\(UUID().uuidString)"
        return (name, try #require(UserDefaults(suiteName: name)))
    }

    private func persisted(in defaults: UserDefaults) throws -> [Int: PendingPurchase] {
        guard let data = defaults.data(forKey: "pendingPurchase.v2") else { return [:] }
        return try JSONDecoder().decode([Int: PendingPurchase].self, from: data)
    }

    private func purchase(accountID: Int = 42, kind: PurchaseKind = .purchase, wasOwned: Bool = false,
                          baseline: PaidOrderSnapshot? = nil) -> PendingPurchase {
        PendingPurchase(attempt: PurchaseAttempt(
            accountID: accountID, discID: "sample-disc", kind: kind,
            amount: PurchaseAmount(cents: 1500)!, wasOwned: wasOwned, baseline: baseline,
            startedAt: Date(timeIntervalSince1970: 1_800_000_000)
        ), title: "Sample Album")
    }

    private func orders(ids: Set<String> = ["existing-order"], kind: PurchaseKind = .boost,
                        fetchedAt: TimeInterval = 1_800_000_001) -> PaidOrderSnapshot {
        PaidOrderSnapshot(accountID: 42, kind: kind, orderIDs: ids, orders: [],
                          hasMore: false, fetchedAt: Date(timeIntervalSince1970: fetchedAt))
    }

    @Test func beginningAnotherPaymentKeepsOriginalPendingAttempt() throws {
        let storage = try makeDefaults()
        defer { storage.defaults.removePersistentDomain(forName: storage.name) }
        let store = PurchaseStore(accountID: { 42 }, defaults: storage.defaults)
        let first = purchase()
        try store.begin(first)

        #expect(throws: PurchaseFlowError.self) { try store.begin(purchase()) }
        #expect(store.current?.id == first.id)
        #expect(store.state == .waiting)

        let restored = PurchaseStore(accountID: { 42 }, defaults: storage.defaults)
        #expect(restored.current?.id == first.id)
    }

    @Test func accountMismatchCannotBeginPayment() throws {
        let storage = try makeDefaults()
        defer { storage.defaults.removePersistentDomain(forName: storage.name) }
        let store = PurchaseStore(accountID: { 7 }, defaults: storage.defaults)
        #expect(throws: DizzyError.self) { try store.begin(purchase()) }
        #expect(store.current == nil)
        #expect(storage.defaults.data(forKey: "pendingPurchase.v2") == nil)
    }

    @Test(arguments: [false, true])
    func pausingOrForgettingInvalidatesLateOwnershipResponse(forget: Bool) async throws {
        let storage = try makeDefaults()
        defer { storage.defaults.removePersistentDomain(forName: storage.name) }
        let gate = OwnershipGate()
        let store = PurchaseStore(accountID: { 42 }, defaults: storage.defaults,
                                  ownership: { await gate.fetch($0) }, sleep: {})
        let pending = purchase()
        try store.begin(pending)
        let check = Task { await store.check() }
        _ = await gate.entered.value()
        #expect(store.state == .checking)

        if forget { store.forget() } else { store.pause() }
        gate.result.send(true)
        await check.value

        #expect(store.state == .waiting)
        #expect(store.current?.id == (forget ? nil : pending.id))
        #expect((storage.defaults.data(forKey: "pendingPurchase.v2") == nil) == forget)
    }

    @Test func switchingAccountsIgnoresInflightResultButRetainsOriginalMetadata() async throws {
        let storage = try makeDefaults()
        defer { storage.defaults.removePersistentDomain(forName: storage.name) }
        let account = AccountContext()
        let gate = OwnershipGate()
        let store = PurchaseStore(accountID: { account.id }, defaults: storage.defaults,
                                  ownership: { await gate.fetch($0) }, sleep: {})
        let pending = purchase()
        try store.begin(pending)
        let check = Task { await store.check() }
        _ = await gate.entered.value()

        account.id = 7
        store.accountDidChange()
        gate.result.send(true)
        await check.value
        #expect(store.state == .waiting)
        #expect(store.current == nil)
        #expect(try persisted(in: storage.defaults)[42]?.id == pending.id)
        #expect(storage.defaults.data(forKey: "pendingPurchase.v2") != nil)

        account.id = 42
        store.accountDidChange()
        #expect(store.current?.id == pending.id)
        #expect(store.state == .waiting)
    }

    @Test func newlyOwnedAlbumConfirmsAndStopsFurtherPolling() async throws {
        let storage = try makeDefaults()
        defer { storage.defaults.removePersistentDomain(forName: storage.name) }
        var ownershipCalls = 0
        var sleepCalls = 0
        let store = PurchaseStore(accountID: { 42 }, defaults: storage.defaults, ownership: { discID in
            #expect(discID == "sample-disc")
            ownershipCalls += 1
            return ownershipCalls == 2
        }, orders: { _, _ in
            Issue.record("First purchase should verify ownership, not enumerate orders")
            return orders()
        }, sleep: { sleepCalls += 1 })
        try store.begin(purchase())
        await store.check()

        #expect(store.state == .confirmed)
        #expect(store.failure == nil)
        #expect(ownershipCalls == 2)
        #expect(sleepCalls == 1)
        #expect(storage.defaults.data(forKey: "pendingPurchase.v2") == nil)

        await store.check()
        #expect(ownershipCalls == 2)
    }

    @Test func alreadyOwnedAlbumNeverConfirmsBoostWithoutANewPaidOrder() async throws {
        let storage = try makeDefaults()
        defer { storage.defaults.removePersistentDomain(forName: storage.name) }
        var ownershipCalls = 0
        var orderCalls = 0
        let baseline = orders(fetchedAt: 1_799_999_999)
        let store = PurchaseStore(accountID: { 42 }, defaults: storage.defaults, ownership: { _ in
            ownershipCalls += 1
            return true
        }, orders: { accountID, kind in
            #expect(accountID == 42)
            #expect(kind == .boost)
            orderCalls += 1
            return orders()
        }, sleep: {})
        try store.begin(purchase(kind: .boost, wasOwned: true, baseline: baseline))
        await store.check()

        #expect(store.state == .unconfirmed)
        #expect(ownershipCalls == 0)
        #expect(orderCalls == 6)
        #expect(storage.defaults.data(forKey: "pendingPurchase.v2") != nil)
    }

    @Test func restoredMetadataWaitsForExplicitCheckAndConcurrentChecksShareOnePoll() async throws {
        let storage = try makeDefaults()
        defer { storage.defaults.removePersistentDomain(forName: storage.name) }
        let pending = purchase()
        let original = PurchaseStore(accountID: { 42 }, defaults: storage.defaults)
        try original.begin(pending)

        let gate = OwnershipGate()
        let restored = PurchaseStore(accountID: { 42 }, defaults: storage.defaults,
                                     ownership: { await gate.fetch($0) }, sleep: {})
        #expect(restored.current?.attempt == pending.attempt)
        #expect(restored.current?.title == pending.title)
        #expect(restored.state == .waiting)
        #expect(gate.discIDs.isEmpty)

        let first = Task { await restored.check() }
        _ = await gate.entered.value()
        let secondStarted = Signal<Bool>()
        let second = Task {
            secondStarted.send(true)
            await restored.check()
        }
        _ = await secondStarted.value()
        #expect(gate.discIDs == ["sample-disc"])
        gate.result.send(true)
        await first.value
        await second.value
        #expect(restored.state == .confirmed)
        #expect(gate.discIDs == ["sample-disc"])
    }

    @Test func independentlyCancelledRequestLeavesNoEndlessCheckingState() async throws {
        let storage = try makeDefaults()
        defer { storage.defaults.removePersistentDomain(forName: storage.name) }
        let store = PurchaseStore(accountID: { 42 }, defaults: storage.defaults, ownership: { _ in
            throw CancellationError()
        }, sleep: {})
        try store.begin(purchase())
        await store.check()
        #expect(store.state == .waiting)
        #expect(store.current != nil)
    }

    @Test func differentAccountsKeepSeparatePendingPaymentsAcrossRestartAndForget() throws {
        let storage = try makeDefaults()
        defer { storage.defaults.removePersistentDomain(forName: storage.name) }
        let account = AccountContext()
        let store = PurchaseStore(accountID: { account.id }, defaults: storage.defaults)
        let first = purchase()
        let second = purchase(accountID: 7)
        try store.begin(first)
        account.id = 7
        store.accountDidChange()
        #expect(store.current == nil)
        try store.begin(second)
        #expect(store.current?.id == second.id)
        #expect(try persisted(in: storage.defaults).count == 2)

        let restored = PurchaseStore(accountID: { account.id }, defaults: storage.defaults)
        #expect(restored.current?.id == second.id)
        account.id = 42
        restored.accountDidChange()
        #expect(restored.current?.id == first.id)
        restored.forget()
        #expect(restored.current == nil)
        #expect(try persisted(in: storage.defaults)[7]?.id == second.id)
        #expect(try persisted(in: storage.defaults)[42] == nil)

        account.id = 7
        let restartedAgain = PurchaseStore(accountID: { account.id }, defaults: storage.defaults)
        #expect(restartedAgain.current?.id == second.id)
        account.id = nil
        restartedAgain.accountDidChange()
        restartedAgain.forget()
        #expect(try persisted(in: storage.defaults)[7]?.id == second.id)
    }

    @Test func confirmingOneAccountPreservesOthersAndOnlyKeepsSuccessInMemory() async throws {
        let storage = try makeDefaults()
        defer { storage.defaults.removePersistentDomain(forName: storage.name) }
        let account = AccountContext()
        let store = PurchaseStore(accountID: { account.id }, defaults: storage.defaults,
                                  ownership: { _ in true }, sleep: {})
        let first = purchase()
        let second = purchase(accountID: 7)
        try store.begin(first)
        account.id = 7
        store.accountDidChange()
        try store.begin(second)
        account.id = 42
        store.accountDidChange()
        await store.check()

        #expect(store.state == .confirmed)
        #expect(store.current?.id == first.id)
        let saved = try persisted(in: storage.defaults)
        #expect(saved[42] == nil)
        #expect(saved[7]?.id == second.id)
        let restored = PurchaseStore(accountID: { account.id }, defaults: storage.defaults)
        #expect(restored.current == nil)
        store.forget()
        #expect(try persisted(in: storage.defaults)[7]?.id == second.id)

        account.id = 7
        store.accountDidChange()
        #expect(store.state == .waiting)
        #expect(store.current?.id == second.id)
        store.forget()
        #expect(storage.defaults.data(forKey: "pendingPurchase.v2") == nil)
    }

    @Test func legacyPendingPaymentMigratesWithoutOverwritingAnotherAccount() throws {
        let storage = try makeDefaults()
        defer { storage.defaults.removePersistentDomain(forName: storage.name) }
        let first = purchase()
        let second = purchase(accountID: 7)
        storage.defaults.set(try JSONEncoder().encode(first), forKey: "pendingPurchase.v1")
        storage.defaults.set(try JSONEncoder().encode([7: second]), forKey: "pendingPurchase.v2")
        let account = AccountContext()
        account.id = 7
        let store = PurchaseStore(accountID: { account.id }, defaults: storage.defaults)

        #expect(store.current?.id == second.id)
        #expect(storage.defaults.data(forKey: "pendingPurchase.v1") == nil)
        #expect(try persisted(in: storage.defaults)[42]?.id == first.id)
        #expect(try persisted(in: storage.defaults)[7]?.id == second.id)
        account.id = 42
        store.accountDidChange()
        #expect(store.current?.id == first.id)
    }
}
