import Combine
import SwiftUI

struct DiscDetailView: View {
    @Environment(OfflineLibraryStore.self) private var offline
    @Environment(AccountLibraryMirror.self) private var accountLibrary
    @Environment(SavedLibraryStore.self) private var savedLibrary
    @Environment(PlaybackHistoryStore.self) private var playbackHistory
    @State private var model: DiscDetailModel

    let initialArtworkURL: URL?

    init(id: String, cachedModel: DiscDetailModel? = nil, initialArtworkURL: URL? = nil) {
        self.initialArtworkURL = initialArtworkURL
        _model = State(initialValue: cachedModel ?? DiscDetailModel(id: id))
    }

    private var displayedArtworkURL: URL? {
        offline.collection(provider: "dizzylab", kind: "album", id: model.id)?.coverURL
            ?? model.detail.value?.summary.coverURL ?? initialArtworkURL ?? libraryArtworkURL
    }

    private var libraryArtworkURL: URL? {
        accountLibrary.collections.first {
            $0.providerID == "dizzylab" && $0.kind == .album && $0.itemID == model.id
        }?.coverURL ?? savedLibrary.items.first {
            $0.providerID == "dizzylab" && $0.kind == .album && $0.itemID == model.id
        }?.coverURL ?? playbackHistory.entries.first {
            $0.providerID == "dizzylab" && $0.itemID == model.id
        }?.coverURL
    }

    /// 已扫描的专辑、详情或失败信息有了，内容就淡入。
    private var isContentReady: Bool {
        offline.collection(provider: "dizzylab", kind: "album", id: model.id) != nil
            || model.detail.value != nil || model.detail.failure != nil
    }

    var body: some View {
        // Keep background state alive when loading content is replaced by album details.
        AlbumDetailScrollView(artworkURL: initialArtworkURL ?? libraryArtworkURL ?? displayedArtworkURL,
                              isContentReady: isContentReady) {
            if let album = offline.collection(provider: "dizzylab", kind: "album", id: model.id) {
                // 已扫描到的专辑立即显示，不发起详情或试听时长请求。
                DiscDetailContent(detail: album.detail, tracks: album.tracks, artworkURL: album.coverURL)
            } else {
                Group {
                    if let detail = model.detail.value {
                        DiscDetailContent(detail: detail, tracks: model.tracks(of: detail))
                    } else {
                        if let failure = model.detail.failure {
                            LoadFailureView(message: failure) { await model.detail.load() }
                        } else {
                            VStack(spacing: 0) {
                                AlbumHero(artworkURL: displayedArtworkURL, title: "专辑名称", metadata: "歌曲数量", reservesTitleSpace: true, metadataIsPlaceholder: true, titleIsPlaceholder: true) {
                                    Text("创作者").redacted(reason: .placeholder)
                                } actions: {
                                    AlbumPlaybackActions(isEmpty: true) { _ in }
                                }

                                ContentSkeleton(layout: .numberedSongs, count: 6)
                                    .padding(.horizontal, 20)
                            }
                        }
                        Color.clear.frame(height: 0).task { await model.detail.loadIfNeeded() }
                    }
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
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Menu {
                    ShareLink(item: DizzyURL.disc(model.id)) { Label("分享", systemImage: "square.and.arrow.up") }
                } label: {
                    Label("更多", systemImage: "ellipsis")
                }
            }
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
    @Environment(AccountLibraryMirror.self) private var accountLibrary
    @State private var purchaseSheet: PurchaseSheet?
    @State private var checkedLocalTrackIDs: Set<String>?

    private var summary: DiscSummary { detail.summary }
    private var localAlbum: OfflineAlbum? { offline.collection(provider: "dizzylab", kind: "album", id: detail.id) }
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
        LazyVStack(alignment: .leading, spacing: 0) {
            header
            if !detail.description.isEmpty || !detail.credits.isEmpty {
                AlbumDescriptionExcerpt(title: summary.title, subtitle: summary.labelName, sections: [
                    .init(title: "介绍", text: detail.description),
                    .init(title: "曲目与制作人员", text: detail.credits)
                ], accessibilityTitle: "专辑介绍")
                    .padding(.horizontal, 20)
                    .padding(.bottom, 20)
            }
            DiscStoreCard(detail: detail, hasMissingLocalFiles: hasMissingLocalFiles) {
                purchaseSheet = PurchaseSheet(summary: summary)
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 16)
            trackList
            trackFooter
            VStack(alignment: .leading, spacing: 32) {
                if !summary.tags.isEmpty { tags }
                DiscCommunityView(discID: detail.id)
            }
            .padding(.top, 28)
        }
        .padding(.bottom, 32)
        .onAppear { CollectionTrackIndex.shared.record(CollectionTrackIndex.key(provider: "dizzylab", kind: "album", id: detail.id), tracks: tracks) }
        .task(id: LocalAvailabilityRequest(discID: detail.id, revision: offline.contentRevision)) {
            checkedLocalTrackIDs = nil
            do {
                let keys = try await offline.localTrackKeys(provider: "dizzylab", collectionID: detail.id)
                let ids = Set(keys.map(\.itemID))
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
                  metadata: ([detail.releaseDate, summary.isHiRes ? "Hi-Res" : nil]
                    .compactMap { $0 }).joined(separator: " · ")) {
            if let label = summary.labelName {
                NavigationLink(value: AppRoute.label(name: label)) { Text(label) }
                    .buttonStyle(.plain)
                    .foregroundStyle(.primary)
            }
        } actions: {
            AlbumPlaybackActions(isEmpty: tracks.isEmpty, isPreview: isPreviewOnly, play: { shuffled in
                guard !tracks.isEmpty else { return }
                play(from: shuffled ? Int.random(in: tracks.indices) : 0)
                if player.isShuffled != shuffled { player.toggleShuffle() }
            }) {
                if summary.isOwned || accountLibrary.isDizzyLabAlbumPurchased(summary.id) {
                    Button {} label: {
                        CollectionLibraryActionLabel(isAdded: true)
                    }
                    .disabled(true)
                    .accessibilityLabel("已购专辑，已在资料库")
                } else {
                    SavedLibraryToggle(item: SavedLibraryItem(
                        kind: .album, providerID: "dizzylab", itemID: summary.id, title: summary.title,
                        subtitle: summary.labelName ?? "DizzyLab", coverURL: artworkURL ?? summary.coverURL, addedAt: .now))
                }
            }
            .padding(.horizontal, 20)
        }
    }

    /// 曲目列表末尾的统计，与 Apple Music 相同放在列表下方。
    /// 只能试听时时长是试听片段的长度，不计总时长。
    private var trackFooter: some View {
        let durations = tracks.compactMap(\.duration)
        let minutes = !isPreviewOnly && durations.count == tracks.count && !tracks.isEmpty
            ? Int((durations.reduce(0, +) / 60).rounded()) : nil
        return Text(["\(tracks.count) 首歌曲", minutes.map { "\($0) 分钟" }].compactMap { $0 }.joined(separator: "，"))
            .font(.footnote)
            .foregroundStyle(.secondary)
            .padding(.horizontal, 20)
            .padding(.top, 12)
    }

    private var tags: some View {
        VStack(alignment: .leading, spacing: 10) {
            SectionHeading(title: "标签")
                .padding(.horizontal, 20)
            ScrollView(.horizontal) {
                HStack(spacing: 8) {
                    ForEach(summary.tags, id: \.self) { tag in
                        NavigationLink(value: AppRoute.tag(tag)) { Text(tag) }
                    }
                }
                .font(.subheadline)
                .buttonStyle(.bordered)
                .buttonBorderShape(.capsule)
                .controlSize(.small)
                .tint(.primary)
                .padding(.horizontal, 20)
            }
            .scrollIndicators(.hidden)
        }
    }

    private var trackList: some View {
        LazyVStack(spacing: 0) {
            ForEach(tracks.enumerated(), id: \.element.id) { index, track in
                // 整张都是试听时由购买卡片统一说明，只在部分曲目可完整播放时逐行标注。
                SongRow(track: track, style: .numbered(track.number), isDownloaded: localTrackIDs.contains(track.id),
                        isPreview: !isPreviewOnly && !localTrackIDs.contains(track.id)
                            && (detail.streams[track.number].map(DizzyURL.isPreviewStream) ?? false)) {
                    play(from: index)
                }
            }
        }
        .padding(.horizontal, 20)
    }

    private func play(from index: Int) {
        player.play(tracks, startAt: index, streams: detail.streams)
    }
}

private struct LocalAvailabilityRequest: Hashable {
    let discID: String
    let revision: Int
}

/// 购买与下载卡片。未购买：左边价格，右边「购买」。已购买：一行状态，下面是当前最重要的一件事——
/// 下载入口、下载进度、失败重试或「管理下载」。格式、特典和详细进度都在下载面板里。下载队列的变化只刷新这张卡片。
private struct DiscStoreCard: View {
    let detail: DiscDetail
    let hasMissingLocalFiles: Bool
    let purchase: () -> Void
    @Environment(OfflineLibraryStore.self) private var offline
    @Environment(DownloadStore.self) private var downloads
    @Environment(\.colorScheme) private var colorScheme
    @State private var showsDownloads = false
    @State private var isRetrying = false

    private var summary: DiscSummary { detail.summary }
    private var localAlbum: OfflineAlbum? { offline.collection(provider: "dizzylab", kind: "album", id: detail.id) }
    private var canDownload: Bool { summary.isOwned || localAlbum != nil }
    /// 专辑优先于特典。
    private var activeJob: DownloadJob? {
        let active = downloads.jobs.filter { $0.discID == detail.id && $0.isActive }
        return active.first { !$0.isGift } ?? active.first
    }
    /// 只看专辑、特典各自最近的一次任务，旧的失败记录不会盖过之后成功的下载。
    private var failedJob: DownloadJob? {
        [false, true].lazy
            .compactMap { isGift in downloads.jobs.first { $0.discID == detail.id && $0.isGift == isGift } }
            .first { $0.canRetry }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            if summary.isOwned {
                ownedStatus
            } else {
                purchaseRow
            }
            if localAlbum != nil && hasMissingLocalFiles {
                HStack(alignment: .firstTextBaseline) {
                    Label("部分本地文件不可用", systemImage: "exclamationmark.triangle.fill")
                        .font(.footnote)
                        .foregroundStyle(.orange)
                    Spacer()
                    Button("重新扫描") { Task { await offline.scan() } }
                        .font(.footnote.weight(.semibold))
                        .disabled(offline.isScanning)
                }
            }
            if canDownload {
                if let activeJob {
                    DownloadEntryProgress(job: activeJob) { showsDownloads = true }
                } else if let failedJob {
                    failure(failedJob)
                } else if localAlbum == nil {
                    downloadEntry
                } else {
                    Button { showsDownloads = true } label: {
                        Label("管理下载", systemImage: "arrow.down.circle").frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.bordered)
                    .buttonBorderShape(.roundedRectangle(radius: 14))
                    .controlSize(.large)
                    .tint(DizzyPalette.download)
                    .fontWeight(.semibold)
                    .accessibilityHint("换个格式重新下载，或下载特典")
                }
            }
        }
        .padding(16)
        .background(.fill.quaternary, in: .rect(cornerRadius: 20))
        .sheet(isPresented: $showsDownloads) {
            DownloadAlbumView(detail: detail, isDownloaded: localAlbum != nil)
                .restoringAppColorScheme()
        }
    }

    private var ownedStatus: some View {
        HStack(spacing: 10) {
            Image(systemName: "checkmark.seal.fill")
                .font(.title3)
                .foregroundStyle(DizzyPalette.success)
            VStack(alignment: .leading, spacing: 1) {
                Text("已购买")
                    .font(.headline)
                    .foregroundStyle(DizzyPalette.success)
                Text(localAlbum == nil ? "尚未下载到本设备" : "已下载到本设备")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 8)
            Button(action: purchase) { Label("BOOST", systemImage: "heart") }
                .font(.subheadline.weight(.semibold))
                .buttonStyle(.bordered)
                .buttonBorderShape(.capsule)
                .controlSize(.small)
                .tint(.primary)
                .accessibilityLabel("BOOST · 追加支持创作者")
        }
    }

    @ViewBuilder private var purchaseRow: some View {
        HStack(alignment: .center, spacing: 12) {
            if let price = summary.price {
                VStack(alignment: .leading, spacing: 2) {
                    Text("数字专辑").font(.footnote).foregroundStyle(.secondary)
                    HStack(alignment: .firstTextBaseline, spacing: 6) {
                        Text(price.text).font(.title3.weight(.semibold))
                        if case .deal(let original, _) = price {
                            Text(PriceTag.yuan(original)).font(.footnote).strikethrough().foregroundStyle(.secondary)
                        }
                    }
                }
            }
            Spacer(minLength: 8)
            Button(action: purchase) {
                Text(summary.price == .free ? "获取" : "购买").frame(minWidth: 64)
            }
            .buttonStyle(.borderedProminent)
            .buttonBorderShape(.capsule)
            .tint(.primary)
            .foregroundStyle(colorScheme == .dark ? Color.black : Color.white)
            .fontWeight(.semibold)
            .accessibilityLabel("购买 / 支持创作者")
        }
    }

    private var downloadEntry: some View {
        VStack(alignment: .leading, spacing: 10) {
            Button { showsDownloads = true } label: {
                HStack(spacing: 10) {
                    Image(systemName: "arrow.down.to.line")
                    Text("下载到本设备").frame(maxWidth: .infinity, alignment: .leading)
                    Image(systemName: "chevron.right").font(.footnote.weight(.bold))
                }
                .padding(.horizontal, 4)
            }
            .buttonStyle(.borderedProminent)
            .buttonBorderShape(.roundedRectangle(radius: 14))
            .controlSize(.large)
            .tint(DizzyPalette.download)
            .fontWeight(.semibold)
            .accessibilityHint("选择格式和特典")
        }
    }

    private func failure(_ job: DownloadJob) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top, spacing: 10) {
                Image(systemName: "exclamationmark.circle.fill")
                    .font(.title3)
                    .foregroundStyle(DizzyPalette.danger)
                VStack(alignment: .leading, spacing: 2) {
                    Text(job.isGift ? "特典下载没有完成" : "下载没有完成")
                        .font(.subheadline.weight(.semibold))
                    Text(job.statusText)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                Button { Task { await downloads.remove(job) } } label: {
                    Image(systemName: "xmark")
                        .font(.footnote.weight(.bold))
                        .frame(width: 32, height: 32)
                        .contentShape(.rect)
                }
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)
                .accessibilityLabel("不再显示这条下载记录")
            }
            HStack(spacing: 8) {
                Button {
                    isRetrying = true
                    Task {
                        await downloads.retry(job)
                        isRetrying = false
                    }
                } label: { Text("重试").frame(maxWidth: .infinity) }
                .buttonStyle(.borderedProminent)
                .tint(DizzyPalette.download)
                .disabled(isRetrying || offline.isScanning || !downloads.isAvailable(job.providerID))
                .accessibilityHint("重新获取下载链接并开始下载")
                Button { showsDownloads = true } label: {
                    Text(job.isGift ? "打开下载" : "换个格式").frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
                .tint(.primary)
            }
            .buttonBorderShape(.roundedRectangle(radius: 12))
            .fontWeight(.semibold)
        }
    }
}

struct PurchaseSheet: Identifiable {
    let summary: DiscSummary
    var id: String { summary.id }
}

