import AppKit
import Combine
import SwiftUI

/// 专辑页。已下载的专辑直接用本地清单显示，不再请求详情；其余按 iOS 的 DiscDetailView 加载。
struct AlbumPage: View {
    @Environment(BrowsingHistoryStore.self) private var history
    @Environment(OfflineLibraryStore.self) private var offline
    @State private var model: DiscDetailModel

    init(id: String) {
        _model = State(initialValue: DiscDetailModel(id: id))
    }

    private var historySummary: DiscSummary? {
        offline.album(id: model.id)?.detail.summary ?? model.detail.value?.summary
    }

    var body: some View {
        Group {
            if let album = offline.album(id: model.id) {
                AlbumContent(detail: album.detail, tracks: album.tracks, artworkURL: album.coverURL)
            } else {
                LoadablePage(state: model.detail, webURL: DizzyURL.disc(model.id)) { detail in
                    AlbumContent(detail: detail, tracks: model.tracks(of: detail))
                }
                .task { await model.loadDurations() }
                .task(id: model.detail.value?.id) {
                    if let detail = model.detail.value {
                        await model.loadPreviewDurations(for: detail)
                    }
                }
                .id(ObjectIdentifier(model))
            }
        }
        .navigationTitle(historySummary?.title ?? String(localized: "专辑"))
        .onAppear { history.visit(id: model.id, summary: historySummary) }
        .onChange(of: historySummary) { _, summary in
            if let summary { history.update(summary) }
        }
        .onReceive(NotificationCenter.default.publisher(for: .dizzyAccountDidChange)) { _ in
            // 重新读取当前账号的购买权限，不复用上一会话的下载入口。
            model = DiscDetailModel(id: model.id)
        }
        .onReceive(NotificationCenter.default.publisher(for: .dizzyPurchaseDidComplete)) { notification in
            if notification.object as? String == model.id { model = DiscDetailModel(id: model.id, fresh: true) }
        }
        .pageRefresh { model = DiscDetailModel(id: model.id, fresh: true) }
    }
}

private struct LocalAvailabilityRequest: Hashable {
    let discID: String
    let revision: Int
}

private struct AlbumContent: View {
    let detail: DiscDetail
    let tracks: [Track]
    var artworkURL: URL?
    @Environment(MacAppModel.self) private var app
    @Environment(PlayerStore.self) private var player
    @Environment(OfflineLibraryStore.self) private var offline
    @Environment(DownloadStore.self) private var downloads
    @State private var checkedLocalTrackIDs: Set<String>?
    @State private var downloadTarget: DownloadTarget?

    private var summary: DiscSummary { detail.summary }
    private var localAlbum: OfflineAlbum? { offline.album(id: detail.id) }
    private var localTrackIDs: Set<String> {
        checkedLocalTrackIDs ?? Set(localAlbum?.manifest.entries.map { $0.track.id } ?? [])
    }
    private var hasMissingLocalFiles: Bool {
        localAlbum != nil && checkedLocalTrackIDs != nil && tracks.contains { !localTrackIDs.contains($0.id) }
    }
    /// 没有任何完整版地址，说明只能试听。
    private var isPreviewOnly: Bool {
        !tracks.contains(where: { localTrackIDs.contains($0.id) })
            && !detail.streams.isEmpty
            && detail.streams.values.allSatisfy(DizzyURL.isPreviewStream)
    }
    private var albumArtist: String? {
        Dictionary(grouping: tracks.map(\.artists), by: { $0 }).max { $0.value.count < $1.value.count }?.key
    }
    private var activeJob: DownloadJob? { downloads.jobs.first { $0.discID == detail.id && !$0.isGift && $0.isActive } }
    private var failedJob: DownloadJob? { downloads.jobs.first { $0.discID == detail.id && !$0.isGift && $0.canRetry } }
    private var giftJob: DownloadJob? {
        downloads.jobs.first { $0.discID == detail.id && $0.isGift && ($0.isActive || $0.canRetry) }
    }

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 26) {
                header
                status
                TrackList(tracks: tracks, isPreview: isPreview, albumArtist: albumArtist) { play(from: $0) }
                    .padding(.horizontal, -10)
                TrackListFooter(tracks: tracks, releaseDate: detail.releaseDate)
                if !summary.tags.isEmpty { tags }
                if !detail.credits.isEmpty {
                    VStack(alignment: .leading, spacing: 8) {
                        SectionTitle(String(localized: "曲目与制作人员"))
                        ExpandableText(text: detail.credits, collapsedLines: 6)
                    }
                }
                CommunitySection(discID: detail.id)
            }
            .padding(.horizontal, PageMetrics.margin)
            .padding(.top, 14)
            .padding(.bottom, 28)
        }
        .task(id: LocalAvailabilityRequest(discID: detail.id, revision: offline.contentRevision)) {
            checkedLocalTrackIDs = nil
            do {
                let ids = try await offline.availableTrackIDs(discID: detail.id)
                try Task.checkCancellation()
                checkedLocalTrackIDs = ids
            } catch is CancellationError {
                return
            } catch {
                guard !Task.isCancelled else { return }
                checkedLocalTrackIDs = []
            }
        }
        .sheet(item: $downloadTarget) { DownloadSheet(detail: $0.detail, isGift: $0.isGift) }
    }

    private var header: some View {
        AlbumHeader(artworkURL: artworkURL ?? summary.coverURL, title: summary.title,
                    metadata: [detail.releaseDate, summary.isHiRes ? "Hi-Res" : nil].compactMap { $0 }.joined(separator: " · ")) {
            if let label = summary.labelName {
                NavigationLink(label, value: AppRoute.label(name: label))
                    .buttonStyle(.plain)
            }
        } actions: {
            AlbumPlayButtons(isEmpty: tracks.isEmpty, isPreview: isPreviewOnly) { shuffled in
                app.play(tracks, streams: detail.streams, shuffled: shuffled)
            }
            if summary.isOwned {
                Button { downloadTarget = DownloadTarget(detail: detail) } label: {
                    Label(failedJob == nil ? "下载" : "重新下载", systemImage: "arrow.down.circle")
                }
                .buttonStyle(.bordered)
                .fixedSize()
                .disabled(activeJob != nil)
                .help("选择保存文件夹和下载格式")
            }
            Button { app.purchaseTarget = summary } label: {
                switch (summary.isOwned, summary.price) {
                case (true, _): Label("BOOST", systemImage: "heart")
                case (false, .free?): Label("免费获取", systemImage: "bag")
                case (false, .price(let value)?), (false, .deal(_, let value)?): Label("购买 \(PriceTag.yuan(value))", systemImage: "bag")
                default: Label("购买 / 支持", systemImage: "bag")
                }
            }
            .buttonStyle(.bordered)
            .fixedSize()
            .help(summary.isOwned ? "BOOST · 追加支持创作者" : "购买 / 支持创作者")
            Menu {
                if summary.isOwned || localAlbum != nil {
                    Button("下载特典", systemImage: "gift") { downloadTarget = DownloadTarget(detail: detail, isGift: true) }
                    Divider()
                }
                if let label = summary.labelName {
                    Button("前往社团「\(label)」", systemImage: "music.mic") { app.navigation.open(.label(name: label)) }
                }
                Link(destination: DizzyURL.disc(summary.id)) { Label("在浏览器中打开", systemImage: "safari") }
                Button("拷贝链接", systemImage: "link") {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(DizzyURL.disc(summary.id).absoluteString, forType: .string)
                }
            } label: {
                Image(systemName: "ellipsis")
            }
            .menuIndicator(.hidden)
            .buttonStyle(.bordered)
            .buttonBorderShape(.circle)
            .fixedSize()
            .help("更多")
        } footer: {
            if !detail.description.isEmpty {
                ExpandableText(text: detail.description, collapsedLines: 3)
            }
        }
    }

    @ViewBuilder private var status: some View {
        let hasStatus = summary.isOwned || hasMissingLocalFiles || activeJob != nil || failedJob != nil || giftJob != nil || isPreviewOnly
        if hasStatus {
            VStack(alignment: .leading, spacing: 10) {
                if summary.isOwned {
                    Label(localAlbum == nil ? "已购买" : "已购买 · 已下载到本地", systemImage: "checkmark.seal.fill")
                        .foregroundStyle(DizzyPalette.success)
                }
                if hasMissingLocalFiles {
                    HStack {
                        Label("部分本地文件不可用，可重新扫描或下载覆盖。", systemImage: "exclamationmark.triangle")
                            .foregroundStyle(Color.dizzyGold)
                        Button("重新扫描") { Task { await offline.scan() } }
                            .disabled(offline.isScanning)
                    }
                }
                ForEach([activeJob ?? failedJob, giftJob].compactMap { $0 }) { job in
                    DownloadJobRow(job: job)
                        .frame(maxWidth: 520)
                }
                if isPreviewOnly {
                    Text("当前为试听片段。购买后可收听完整版并下载到所选文件夹。")
                        .foregroundStyle(.secondary)
                }
            }
            .font(.callout)
        }
    }

    private var tags: some View {
        FlowLayout(spacing: 8, lineSpacing: 8) {
            ForEach(summary.tags, id: \.self) { tag in
                NavigationLink(value: AppRoute.tag(tag)) {
                    Text("#\(tag)")
                        .font(.callout)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 4)
                        .background(.primary.opacity(0.06), in: .capsule)
                        .contentShape(.capsule)
                }
                .buttonStyle(.plain)
                .foregroundStyle(DizzyPalette.info)
            }
        }
    }

    private func isPreview(_ track: Track) -> Bool {
        !localTrackIDs.contains(track.id) && (detail.streams[track.number].map(DizzyURL.isPreviewStream) ?? false)
    }

    private func play(from index: Int) {
        player.play(tracks, startAt: index, streams: detail.streams)
    }
}

struct DownloadTarget: Identifiable {
    let detail: DiscDetail
    var isGift = false
    var id: String { detail.id + (isGift ? "-gift" : "-album") }
}
