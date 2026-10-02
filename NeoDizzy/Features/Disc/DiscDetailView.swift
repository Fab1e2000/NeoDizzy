import Combine
import SwiftUI

@Observable
final class DiscDetailModel {
    let id: String
    let detail: Loadable<DiscDetail>
    /// 曲号 → 完整版时长，来自专辑页 HTML。取不到时为空，不影响页面。
    private(set) var durations: [String: TimeInterval] = [:]
    /// 曲号 → 试听片段时长。未购买时列表显示这个长度。
    private(set) var previewDurations: [String: TimeInterval] = [:]
    private var hasRequestedDurations = false
    private var hasRequestedPreviewDurations = false

    init(id: String, fresh: Bool = false) {
        self.id = id
        detail = Loadable { try await DizzyAPI.shared.discDetail(id: id, fresh: fresh) }
    }

    /// 成功取到一次就不再请求，即使页面里本来就没有时长；失败或被取消时下次进入再取。
    func loadDurations() async {
        guard !hasRequestedDurations else { return }
        guard let durations = try? await DizzyPages.shared.trackDurations(discID: id) else { return }
        self.durations = durations
        hasRequestedDurations = true
    }

    /// 每个试听文件发一个 HEAD 请求取大小，换算成时长。
    func loadPreviewDurations(for detail: DiscDetail) async {
        guard !hasRequestedPreviewDurations else { return }
        let previews = detail.streams.filter { DizzyURL.isPreviewStream($0.value) }
        guard !previews.isEmpty else {
            hasRequestedPreviewDurations = true
            return
        }
        let results = await withTaskGroup(of: (String, TimeInterval?).self) { group in
            for (number, url) in previews {
                group.addTask { (number, try? await DizzyAPI.shared.previewDuration(of: url)) }
            }
            var results: [String: TimeInterval] = [:]
            for await (number, duration) in group {
                results[number] = duration
            }
            return results
        }
        previewDurations = results
        hasRequestedPreviewDurations = !results.isEmpty
    }

    func tracks(of detail: DiscDetail) -> [Track] {
        detail.tracks.map { track in
            var track = track
            let isPreview = detail.streams[track.number].map(DizzyURL.isPreviewStream) ?? false
            track.duration = isPreview ? previewDurations[track.number] : durations[track.number]
            return track
        }
    }
}

struct DiscDetailView: View {
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
                // 已扫描到的专辑立即显示，不发起详情或试听时长请求。
                DiscDetailContent(detail: album.detail, tracks: album.tracks, artworkURL: album.coverURL)
            } else {
                LoadableContent(state: model.detail, webURL: DizzyURL.disc(model.id)) { detail in
                    DiscDetailContent(detail: detail, tracks: model.tracks(of: detail))
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
        .dizzyPageBackground()
        .safeAreaPadding(.top, 5)
        .navigationTitle("")
        .toolbar(.visible, for: .navigationBar)
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(.hidden, for: .navigationBar)
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
    }
}

private struct DiscDetailContent: View {
    let detail: DiscDetail
    let tracks: [Track]
    var artworkURL: URL?
    @Environment(PlayerStore.self) private var player
    @Environment(OfflineLibraryStore.self) private var offline
    @State private var purchaseSheet: PurchaseSheet?
    @State private var checkedLocalTrackIDs: Set<String>?

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

    var body: some View {
        AlbumDetailScrollView(artworkURL: artworkURL ?? summary.coverURL) {
            LazyVStack(alignment: .leading, spacing: 24) {
                header
                trackList
                actions
                if !summary.tags.isEmpty { tags }
                if !detail.description.isEmpty {
                    ExpandableText(title: "介绍", text: detail.description)
                }
                if !detail.credits.isEmpty {
                    ExpandableText(title: "曲目与制作人员", text: detail.credits)
                }
                DiscCommunityView(discID: detail.id)
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 32)
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
        .sheet(item: $purchaseSheet) { sheet in
            PurchaseView(summary: sheet.summary)
        }
    }

    private var header: some View {
        AlbumHero(artworkURL: artworkURL ?? summary.coverURL, title: summary.title,
                  metadata: ([detail.releaseDate, "\(tracks.count) 首", summary.isHiRes ? "Hi-Res" : nil]
                    .compactMap { $0 }).joined(separator: " · ")) {
            if let label = summary.labelName {
                NavigationLink(value: AppRoute.label(name: label)) { Text(label) }
                    .buttonStyle(.plain)
            }
        } actions: {
            AlbumPlaybackActions(isEmpty: tracks.isEmpty, isPreview: isPreviewOnly,
                                 webURL: DizzyURL.disc(summary.id)) { shuffled in
                guard !tracks.isEmpty else { return }
                play(from: shuffled ? Int.random(in: tracks.indices) : 0)
                if player.isShuffled != shuffled { player.toggleShuffle() }
            }
        }
    }

    private var actions: some View {
        VStack(spacing: 12) {
            HStack {
                if summary.isOwned {
                    Label("已购买", systemImage: "checkmark.seal.fill")
                        .foregroundStyle(DizzyPalette.success)
                } else if let price = summary.price { PriceText(price: price) }
                Spacer()
            }
            .font(.subheadline)
            DiscDownloadSection(detail: detail, hasMissingLocalFiles: hasMissingLocalFiles) {
                purchaseSheet = PurchaseSheet(summary: summary)
            }
            if isPreviewOnly {
                Text("当前为试听片段。购买后可收听完整版并下载到所选文件夹。")
                    .font(.caption)
                    .foregroundStyle(DizzyPalette.mutedText)
                    .multilineTextAlignment(.center)
            }
        }
    }

    private var tags: some View {
        FlowLayout(spacing: 8, lineSpacing: 8) {
            ForEach(summary.tags, id: \.self) { tag in
                NavigationLink(value: AppRoute.tag(tag)) {
                    Text("#\(tag)")
                        .font(.footnote)
                        .foregroundStyle(DizzyPalette.info)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 5)
                        .background(DizzyPalette.surface, in: .capsule)
                }
                .buttonStyle(.plain)
            }
        }
    }

    private var trackList: some View {
        LazyVStack(spacing: 0) {
            ForEach(tracks.enumerated(), id: \.element.id) { index, track in
                AlbumTrackRow(track: track,
                              isPreview: !localTrackIDs.contains(track.id)
                                && (detail.streams[track.number].map(DizzyURL.isPreviewStream) ?? false)) {
                    play(from: index)
                }
            }
        }
        .padding(.horizontal, -20)
    }

    private func play(from index: Int) {
        player.play(tracks, startAt: index, streams: detail.streams)
    }
}

private struct LocalAvailabilityRequest: Hashable {
    let discID: String
    let revision: Int
}

/// Queue changes are scoped to the download controls, not the cover and track list.
private struct DiscDownloadSection: View {
    let detail: DiscDetail
    let hasMissingLocalFiles: Bool
    let purchase: () -> Void
    @Environment(\.dynamicTypeSize) private var typeSize
    @Environment(OfflineLibraryStore.self) private var offline
    @Environment(DownloadStore.self) private var downloads
    @State private var downloadSheet: DownloadSheet?

    private var summary: DiscSummary { detail.summary }
    private var localAlbum: OfflineAlbum? { offline.album(id: detail.id) }
    private var activeJob: DownloadJob? {
        downloads.jobs.first { $0.discID == detail.id && !$0.isGift && $0.isActive }
    }
    private var failedJob: DownloadJob? {
        downloads.jobs.first { $0.discID == detail.id && !$0.isGift && $0.canRetry }
    }

    var body: some View {
        VStack(spacing: 8) {
            if localAlbum != nil && hasMissingLocalFiles {
                Label("部分本地文件不可用，可重新扫描或下载覆盖。", systemImage: "exclamationmark.triangle")
                    .font(.caption)
                    .foregroundStyle(DizzyPalette.accent)
                Button("重新扫描") { Task { await offline.scan() } }
                    .buttonStyle(.bordered)
                    .disabled(offline.isScanning)
            }
            if let activeJob {
                DownloadJobRow(job: activeJob)
            } else if summary.isOwned {
                if let failedJob {
                    DownloadJobRow(job: failedJob)
                }
                Button {
                    downloadSheet = DownloadSheet(detail: detail)
                } label: {
                    Label(failedJob == nil ? "下载专辑" : "重新选择格式", systemImage: "arrow.down.circle")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .tint(DizzyPalette.download)
                .controlSize(.large)
                .accessibilityHint("选择保存文件夹和下载格式")
            }
            if let giftJob = downloads.jobs.first(where: { $0.discID == detail.id && $0.isGift && ($0.isActive || $0.canRetry) }) {
                DownloadJobRow(job: giftJob)
            }
            let layout = typeSize.isAccessibilitySize ? AnyLayout(VStackLayout(spacing: 10)) : AnyLayout(HStackLayout(spacing: 10))
            layout {
                Button(action: purchase) {
                    Label(summary.isOwned ? "BOOST" : "购买 / 支持", systemImage: "heart")
                        .frame(maxWidth: .infinity, minHeight: 24)
                }
                .tint(DizzyPalette.accent)
                .accessibilityLabel(summary.isOwned ? "BOOST · 追加支持创作者" : "购买 / 支持创作者")
                if summary.isOwned || localAlbum != nil {
                    Button {
                        downloadSheet = DownloadSheet(detail: detail, isGift: true)
                    } label: {
                        Label("下载特典", systemImage: "gift")
                            .frame(maxWidth: .infinity, minHeight: 24)
                    }
                    .tint(DizzyPalette.download)
                    .accessibilityHint("下载后自动解压到专辑目录的特典文件夹")
                }
            }
            .buttonStyle(.bordered).controlSize(.large)

        }
        .sheet(item: $downloadSheet) { sheet in
            DownloadAlbumView(detail: sheet.detail, isGift: sheet.isGift)
        }
    }
}

private struct DownloadSheet: Identifiable {
    let detail: DiscDetail
    var isGift = false
    var id: String { detail.id + (isGift ? "-gift" : "-album") }
}

struct PurchaseSheet: Identifiable {
    let summary: DiscSummary
    var id: String { summary.id }
}

/// 曲目行：序号、标题、艺术家、时长，未购买时标注「试听」。
/// 可折叠的长文本，默认显示前几行。
struct ExpandableText: View {
    let title: LocalizedStringKey
    let text: String
    @State private var isExpanded = false

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            SectionHeading(title: title)
            Text(text)
                .font(.subheadline)
                .foregroundStyle(DizzyPalette.text.opacity(0.85))
                .lineLimit(isExpanded ? nil : 6)
                .textSelection(.enabled)
            Button(isExpanded ? "收起" : "展开") {
                withAnimation(.snappy) { isExpanded.toggle() }
            }
            .font(.subheadline.weight(.semibold))
            .foregroundStyle(DizzyPalette.accent)
        }
    }
}
