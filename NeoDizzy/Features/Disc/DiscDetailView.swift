import Combine
import SwiftUI

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
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Menu {
                    ShareLink(item: DizzyURL.disc(model.id)) { Label("分享", systemImage: "square.and.arrow.up") }
                    Link(destination: DizzyURL.disc(model.id)) { Label("在网页中打开", systemImage: "safari") }
                } label: {
                    Label("更多", systemImage: "ellipsis")
                }
            }
        }
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
            LazyVStack(alignment: .leading, spacing: 0) {
                header
                if !detail.description.isEmpty || !detail.credits.isEmpty {
                    DiscNotesExcerpt(detail: detail)
                        .padding(.horizontal, 20)
                        .padding(.bottom, 20)
                }
                DiscStoreCard(detail: detail, isPreviewOnly: isPreviewOnly, hasMissingLocalFiles: hasMissingLocalFiles) {
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
                  metadata: ([detail.releaseDate, summary.isHiRes ? "Hi-Res" : nil]
                    .compactMap { $0 }).joined(separator: " · ")) {
            if let label = summary.labelName {
                // 与 Apple Music 的艺人名一样用主题色，表示可以点进社团页。
                NavigationLink(value: AppRoute.label(name: label)) { Text(label) }
                    .buttonStyle(.plain)
                    .foregroundStyle(DizzyPalette.accent)
            }
        } actions: {
            AlbumPlaybackActions(isEmpty: tracks.isEmpty, isPreview: isPreviewOnly) { shuffled in
                guard !tracks.isEmpty else { return }
                play(from: shuffled ? Int.random(in: tracks.indices) : 0)
                if player.isShuffled != shuffled { player.toggleShuffle() }
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
                AlbumTrackRow(track: track,
                              isPreview: !isPreviewOnly && !localTrackIDs.contains(track.id)
                                && (detail.streams[track.number].map(DizzyURL.isPreviewStream) ?? false)) {
                    play(from: index)
                }
            }
        }
    }

    private func play(from index: Int) {
        player.play(tracks, startAt: index, streams: detail.streams)
    }
}

private struct LocalAvailabilityRequest: Hashable {
    let discID: String
    let revision: Int
}

/// 购买与下载卡片：左边是价格或「已购买」，右边是当前最重要的一个操作；
/// BOOST、特典这类次要操作放在下方的小按钮里。下载队列的变化只刷新这张卡片。
private struct DiscStoreCard: View {
    let detail: DiscDetail
    let isPreviewOnly: Bool
    let hasMissingLocalFiles: Bool
    let purchase: () -> Void
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
    private var giftJob: DownloadJob? {
        downloads.jobs.first { $0.discID == detail.id && $0.isGift && ($0.isActive || $0.canRetry) }
    }
    private var showsGift: Bool { summary.isOwned || localAlbum != nil }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .center, spacing: 12) {
                status
                Spacer(minLength: 8)
                primaryAction
            }
            if isPreviewOnly && !summary.isOwned {
                Text("现在播放的是试听片段，购买后可收听完整版并下载到所选文件夹。")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
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
            if let job = activeJob ?? failedJob {
                DownloadJobRow(job: job, isEmbedded: true)
            }
            if let giftJob {
                DownloadJobRow(job: giftJob, isEmbedded: true)
            }
            if summary.isOwned || showsGift {
                HStack(spacing: 8) {
                    if summary.isOwned {
                        Button(action: purchase) { Label("BOOST", systemImage: "heart") }
                            .accessibilityLabel("BOOST · 追加支持创作者")
                    }
                    if showsGift {
                        Button { downloadSheet = DownloadSheet(detail: detail, isGift: true) } label: {
                            Label("下载特典", systemImage: "gift")
                        }
                        .accessibilityHint("下载后自动解压到专辑目录的特典文件夹")
                    }
                }
                .font(.subheadline.weight(.semibold))
                .buttonStyle(.bordered)
                .buttonBorderShape(.capsule)
                .controlSize(.small)
                .tint(.primary)
            }
        }
        .padding(16)
        .background(.fill.quaternary, in: .rect(cornerRadius: 20))
        .sheet(item: $downloadSheet) { sheet in
            DownloadAlbumView(detail: sheet.detail, isGift: sheet.isGift)
                .restoringAppColorScheme()
        }
    }

    @ViewBuilder private var status: some View {
        if summary.isOwned {
            VStack(alignment: .leading, spacing: 2) {
                Label("已购买", systemImage: "checkmark.seal.fill")
                    .font(.headline)
                    .foregroundStyle(DizzyPalette.success)
                Text(localAlbum == nil ? "可以收听完整版" : "已下载到本地")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        } else if let price = summary.price {
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
    }

    @ViewBuilder private var primaryAction: some View {
        if !summary.isOwned {
            Button(action: purchase) {
                Text(summary.price == .free ? "获取" : "购买").frame(minWidth: 64)
            }
            .buttonStyle(.borderedProminent)
            .buttonBorderShape(.capsule)
            .tint(DizzyPalette.accent)
            .foregroundStyle(DizzyPalette.onAccent)
            .fontWeight(.semibold)
            .accessibilityLabel("购买 / 支持创作者")
        } else if activeJob == nil {
            Button { downloadSheet = DownloadSheet(detail: detail) } label: {
                Label(failedJob == nil ? "下载" : "重新下载", systemImage: "arrow.down")
            }
            .buttonStyle(.borderedProminent)
            .buttonBorderShape(.capsule)
            .tint(DizzyPalette.download)
            .fontWeight(.semibold)
            .accessibilityHint("选择保存文件夹和下载格式")
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

/// 专辑介绍摘录，与 Apple Music 专辑页的介绍相同：标题下方显示前三行，段落连成一段；
/// 被截断时「更多」接在最后一行末尾，前面的文字渐隐，轻点打开完整的「介绍」和「曲目与制作人员」。
/// 没被截断就是全部内容，不显示「更多」，也不能点。
private struct DiscNotesExcerpt: View {
    let detail: DiscDetail
    @State private var isPresented = false
    @State private var isTruncated = false
    @State private var collapsedHeight: CGFloat = 0
    @State private var moreSize: CGSize = .zero
    private static let lineLimit = 3
    private static let fadeWidth: CGFloat = 32

    private var excerpt: String {
        [detail.description, detail.credits]
            .flatMap { $0.split(whereSeparator: \.isNewline) }
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
            .reduce(into: "") { result, line in
                // 中文行之间直接相连，西文行之间补一个空格。
                if let last = result.last, !Self.isWide(last), !Self.isWide(line.first!) { result += " " }
                result += line
            }
    }

    /// 中日韩文字和全角标点，前后不需要空格。
    private static func isWide(_ character: Character) -> Bool {
        character.unicodeScalars.contains { scalar in
            switch scalar.value {
            case 0x2E80...0x9FFF, 0xAC00...0xD7AF, 0xF900...0xFAFF, 0xFE30...0xFE4F, 0xFF00...0xFFEF: true
            default: false
            }
        }
    }

    var body: some View {
        if isTruncated {
            Button { isPresented = true } label: { content }
                .buttonStyle(.plain)
                .accessibilityLabel("专辑介绍")
                .accessibilityValue(excerpt)
                .accessibilityHint("显示完整介绍")
                .sheet(isPresented: $isPresented) { DiscNotesSheet(detail: detail).restoringAppColorScheme() }
        } else {
            content
                .accessibilityElement(children: .ignore)
                .accessibilityLabel("专辑介绍")
                .accessibilityValue(excerpt)
        }
    }

    private var content: some View {
        styled(Text(excerpt))
            .lineLimit(Self.lineLimit)
            .frame(maxWidth: .infinity, alignment: .leading)
            .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { collapsedHeight = $0 }
            .background {
                // 用不限行数的同一段文字比较高度，判断是否真的被截断。
                styled(Text(excerpt))
                    .fixedSize(horizontal: false, vertical: true)
                    .hidden()
                    .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { full in
                        isTruncated = full > collapsedHeight + 1
                    }
            }
            .mask { if isTruncated { fadeMask } else { Rectangle() } }
            .overlay(alignment: .bottomTrailing) {
                if isTruncated {
                    Text("更多")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.primary)
                        .onGeometryChange(for: CGSize.self) { $0.size } action: { moreSize = $0 }
                }
            }
            .contentShape(.rect)
    }

    private func styled(_ text: Text) -> some View {
        text
            .font(.subheadline)
            .foregroundStyle(.secondary)
            .lineSpacing(2)
            .multilineTextAlignment(.leading)
    }

    /// 最后一行末尾给「更多」让位，文字在它前面渐隐，不会和它挤在一起。
    private var fadeMask: some View {
        VStack(spacing: 0) {
            Rectangle()
            HStack(spacing: 0) {
                Rectangle()
                LinearGradient(colors: [.black, .clear], startPoint: .leading, endPoint: .trailing)
                    .frame(width: Self.fadeWidth)
                Color.clear.frame(width: moreSize.width + 4)
            }
            .frame(height: moreSize.height)
        }
    }
}

private struct DiscNotesSheet: View {
    let detail: DiscDetail
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 28) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(detail.summary.title).font(.title2.bold())
                        if let label = detail.summary.labelName {
                            Text(label).font(.title3).foregroundStyle(.secondary)
                        }
                    }
                    if !detail.description.isEmpty { section("介绍", text: detail.description) }
                    if !detail.credits.isEmpty { section("曲目与制作人员", text: detail.credits) }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(20)
            }
            .navigationTitle("介绍")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button(role: .close) { dismiss() }
                }
            }
        }
    }

    private func section(_ title: LocalizedStringKey, text: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title).font(.headline).accessibilityAddTraits(.isHeader)
            // 网页里常有连续好几个空行，最多保留一个，段落间距才均匀。
            Text(text.replacing(#/\n\s*\n\s*(\n\s*)+/#, with: "\n\n").trimmingCharacters(in: .whitespacesAndNewlines))
                .font(.body).lineSpacing(4).textSelection(.enabled)
        }
    }
}

/// 可折叠的长文本：默认显示前几行，被截断时右下角出现「更多」，与 App Store 的介绍相同。
struct ExpandableText: View {
    let title: LocalizedStringKey
    let text: String
    @State private var isExpanded = false
    @State private var isTruncated = false
    private static let collapsedLines = 4

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            SectionHeading(title: title)
            Text(text)
                .font(.subheadline)
                .lineLimit(isExpanded ? nil : Self.collapsedLines)
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background {
                    // 用不限行数的同一段文字比较高度，判断是否真的被截断。
                    Text(text).font(.subheadline)
                        .fixedSize(horizontal: false, vertical: true)
                        .hidden()
                        .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { full in
                            isTruncated = full > collapsedHeight + 1
                        }
                }
                .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { collapsedHeight = $0 }
            if isTruncated || isExpanded {
                Button(isExpanded ? "收起" : "更多") {
                    withAnimation(.snappy) { isExpanded.toggle() }
                }
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(DizzyPalette.accent)
                .frame(maxWidth: .infinity, alignment: .trailing)
            }
        }
    }

    @State private var collapsedHeight: CGFloat = 0
}
