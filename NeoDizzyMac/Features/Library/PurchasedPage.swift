import Combine
import SwiftUI

/// 已购买：当前账号的已购专辑，保留待核验付款的提示。
struct PurchasedPage: View {
    @Environment(MacAppModel.self) private var model
    @Environment(AccountStore.self) private var account
    @Environment(PurchaseStore.self) private var payments
    @Environment(OfflineLibraryStore.self) private var offline

    var body: some View {
        PageScroll(title: String(localized: "已购买")) {
            if let pending = payments.current {
                Button {
                    model.purchaseTarget = DiscSummary(id: pending.attempt.discID, title: pending.title, coverURL: nil)
                } label: {
                    HStack(spacing: 12) {
                        Image(systemName: payments.state == .confirmed ? "checkmark.seal.fill" : "clock")
                            .font(.title2)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(payments.state == .confirmed ? "付款已到账" : "有一笔待核验的付款").font(.headline)
                            Text(pending.title).foregroundStyle(.secondary).lineLimit(1)
                        }
                        Spacer()
                        Image(systemName: "chevron.right").foregroundStyle(.tertiary)
                    }
                    .padding(14)
                    .background(Color.dizzyAccent.opacity(0.12), in: .rect(cornerRadius: 12))
                    .contentShape(.rect)
                }
                .buttonStyle(.plain)
                .foregroundStyle(Color.dizzyAccent)
                .frame(maxWidth: 560)
            }
            if let userID = model.library.userID, let purchases = model.library.purchases {
                PagedSection(list: purchases, webURL: DizzyURL.purchases(userID: userID), emptyTitle: "还没有购买过专辑",
                             emptySystemImage: "bag") { items in
                    LazyVGrid(columns: PageMetrics.gridColumns, alignment: .leading, spacing: PageMetrics.gridSpacing) {
                        ForEach(items) { item in
                            DiscCard(disc: item.disc, caption: caption(for: item))
                        }
                    }
                }
            } else {
                LoginPromptView(systemImage: "bag", message: "登录后，你购买过的专辑会显示在这里。本地专辑可在「本地库」中播放。")
            }
        }
        .onChange(of: account.account?.userID, initial: true) { _, userID in
            model.library.update(userID: userID)
        }
        .onReceive(NotificationCenter.default.publisher(for: .dizzyPurchaseDidComplete)) { _ in
            Task { await model.library.purchases?.reload() }
        }
        .pageRefresh { await model.library.purchases?.reload() }
    }

    private func caption(for item: PurchasedDisc) -> String? {
        let date = item.purchaseDate.map { String(localized: "购买于 \($0)") }
        return offline.album(id: item.disc.id) == nil ? date : [String(localized: "已下载"), date].compactMap { $0 }.joined(separator: " · ")
    }
}
