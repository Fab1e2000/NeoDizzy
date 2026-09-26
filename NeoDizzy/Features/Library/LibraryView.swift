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

/// 音乐库：已购专辑。下载到文件夹、离线播放在 M3 加入。
struct LibraryView: View {
    @Environment(AccountStore.self) private var account
    @State private var model = LibraryModel()

    var body: some View {
        MainTabPage(tab: .library, onRefresh: { await model.purchases?.reload() }) {
            if let userID = model.userID, let purchases = model.purchases {
                SectionHeading(title: "已购专辑")
                PagedContent(list: purchases, webURL: DizzyURL.purchases(userID: userID), emptyMessage: "还没有购买过专辑。") { items in
                    LazyVGrid(columns: DizzyGrid.columns, alignment: .leading, spacing: 22) {
                        ForEach(items) { item in
                            NavigationLink(value: AppRoute.disc(id: item.disc.id)) {
                                DiscCard(disc: item.disc, caption: item.purchaseDate.map { "购买于 \($0)" })
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
            } else {
                LoginPrompt(systemImage: "music.note.list", message: "登录后，你购买过的专辑会显示在这里。")
            }
        }
        .onChange(of: account.account?.userID, initial: true) { _, userID in
            model.update(userID: userID)
        }
    }
}
