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

/// 已购内容与用户所选文件夹中的离线专辑。
struct LibraryView: View {
    @Environment(AccountStore.self) private var account
    @Environment(OfflineLibraryStore.self) private var offline
    @Environment(PurchaseStore.self) private var payments
    @State private var model = LibraryModel()
    @State private var selection: LibrarySection = .purchased
    @State private var purchaseSheet: PurchaseSheet?

    var body: some View {
        MainTabPage(tab: .library, onRefresh: refresh) {
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
            Picker("音乐库内容", selection: $selection) {
                Text("已购专辑").tag(LibrarySection.purchased)
                Text("已下载").tag(LibrarySection.downloaded)
            }
            .pickerStyle(.segmented)

            switch selection {
            case .purchased:
                purchasedContent
            case .downloaded:
                downloadedContent
            }
        }
        .onChange(of: account.account?.userID, initial: true) { _, userID in
            model.update(userID: userID)
            if userID == nil { selection = .downloaded }
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
                                caption: offline.album(id: item.disc.id) != nil
                                    ? "已下载 · 可离线播放"
                                    : item.purchaseDate.map { "购买于 \($0)" }
                            )
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        } else {
            LoginPrompt(systemImage: "music.note.list", message: "登录后，你购买过的专辑会显示在这里。本地专辑可在「已下载」中播放。")
        }
    }

    @ViewBuilder
    private var downloadedContent: some View {
        OfflineFolderSection()
        SectionHeading(title: "本地专辑")
        if offline.albums.isEmpty {
            VStack(spacing: 12) {
                Image(systemName: "arrow.down.circle")
                    .font(.largeTitle)
                    .accessibilityHidden(true)
                Text(offline.isScanning ? "正在读取文件夹…" : "还没有可离线播放的专辑")
                    .font(.headline)
                Text("选择保存音乐的文件夹后，可以下载已购专辑，也可以重新读取此前通过 NeoDizzy 下载的专辑。")
                    .font(.subheadline)
                    .multilineTextAlignment(.center)
            }
            .foregroundStyle(DizzyPalette.mutedText)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 32)
        } else {
            LazyVGrid(columns: DizzyGrid.columns, alignment: .leading, spacing: 22) {
                ForEach(offline.albums) { album in
                    NavigationLink(value: AppRoute.disc(id: album.discID)) {
                        OfflineAlbumCard(album: album)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    private func refresh() async {
        switch selection {
        case .purchased:
            await model.purchases?.reload()
        case .downloaded:
            await offline.scan()
        }
    }
}

private enum LibrarySection: Hashable {
    case purchased
    case downloaded
}

private struct OfflineAlbumCard: View {
    let album: OfflineAlbum

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            ArtworkImage(url: album.coverURL)
            Text(album.title)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(DizzyPalette.text)
                .lineLimit(2)
                .multilineTextAlignment(.leading)
            if !album.labelName.isEmpty {
                Text(album.labelName)
                    .font(.caption)
                    .foregroundStyle(DizzyPalette.mutedText)
                    .lineLimit(1)
            }
            Label("\(album.tracks.count) 首 · 离线可用", systemImage: "checkmark.circle.fill")
                .font(.caption)
                .foregroundStyle(DizzyPalette.success)
        }
        .contentShape(.rect)
        .accessibilityElement(children: .combine)
    }
}
