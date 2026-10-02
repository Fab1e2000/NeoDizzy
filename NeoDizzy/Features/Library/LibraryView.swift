import SwiftUI

/// 当前账号的已购专辑列表。换账号时整个列表重建。
@Observable
final class LibraryModel {
    private(set) var userID: Int?
    private(set) var purchases: PagedList<PurchasedDisc>?

    func update(userID: Int?) {
        guard userID != self.userID else { return }
        self.userID = userID
        purchases = userID.map { id in
            PagedList { page in try await DizzyPages.shared.purchases(userID: id, page: page) }
        }
    }
}

/// 当前账号的已购买页面，保留付款核验与本地下载状态。
struct PurchasedLibraryView: View {
    @Environment(AccountStore.self) private var account
    @Environment(OfflineLibraryStore.self) private var offline
    @Environment(PurchaseStore.self) private var payments
    @State private var model = LibraryModel()
    @State private var purchaseSheet: PurchaseSheet?

    var body: some View {
        MainTabPage(tab: .purchased, onRefresh: { await model.purchases?.reload() }) {
            if let pending = payments.current {
                Button {
                    purchaseSheet = PurchaseSheet(summary: DiscSummary(id: pending.attempt.discID, title: pending.title, coverURL: nil))
                } label: {
                    HStack {
                        Image(systemName: payments.state == .confirmed ? "checkmark.seal.fill" : "clock")
                        VStack(alignment: .leading, spacing: 3) {
                            Text(payments.state == .confirmed ? "付款已到账" : "有一笔待核验的付款").font(.subheadline.bold())
                            Text(pending.title).font(.caption).lineLimit(1)
                        }
                        Spacer()
                        Image(systemName: "chevron.right").font(.caption)
                    }
                    .padding(14)
                    .background(DizzyPalette.surface, in: .rect(cornerRadius: 12))
                }
                .buttonStyle(.plain)
                .foregroundStyle(DizzyPalette.accent)
            }
            purchasedContent
        }
        .onChange(of: account.account?.userID, initial: true) { _, userID in
            model.update(userID: userID)
        }
        .onReceive(NotificationCenter.default.publisher(for: .dizzyPurchaseDidComplete)) { _ in
            Task { await model.purchases?.reload() }
        }
        .sheet(item: $purchaseSheet) { sheet in PurchaseView(summary: sheet.summary) }
    }

    @ViewBuilder
    private var purchasedContent: some View {
        if let userID = model.userID, let purchases = model.purchases {
            PagedContent(list: purchases, webURL: DizzyURL.purchases(userID: userID), emptyMessage: "还没有购买过专辑。") { items in
                LazyVGrid(columns: DizzyGrid.columns, alignment: .leading, spacing: 22) {
                    ForEach(items) { item in
                        NavigationLink(value: AppRoute.disc(id: item.disc.id)) {
                            DiscCard(
                                disc: item.disc,
                                caption: item.purchaseDate.map { "购买于 \($0)" }
                            )
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        } else {
            LoginPrompt(systemImage: "music.note.list", message: "登录后，你购买过的专辑会显示在这里。本地专辑可在「本地库」中播放。")
        }
    }

}
