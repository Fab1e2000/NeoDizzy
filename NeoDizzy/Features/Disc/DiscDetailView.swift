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

    init(id: String) {
        self.id = id
        detail = Loadable { try await DizzyAPI.shared.discDetail(id: id) }
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
    @State private var model: DiscDetailModel

    init(id: String) {
        _model = State(initialValue: DiscDetailModel(id: id))
    }

    var body: some View {
        LoadableContent(state: model.detail, webURL: DizzyURL.disc(model.id)) { detail in
            DiscDetailContent(detail: detail, tracks: model.tracks(of: detail))
        }
        .task { await model.loadDurations() }
        .task(id: model.detail.value?.id) {
            if let detail = model.detail.value {
                await model.loadPreviewDurations(for: detail)
            }
        }
        .dizzyPageBackground()
        .navigationTitle(model.detail.value?.summary.title ?? "")
        .navigationBarTitleDisplayMode(.inline)
    }
}

private struct DiscDetailContent: View {
    let detail: DiscDetail
    let tracks: [Track]
    @Environment(PlayerStore.self) private var player

    private var summary: DiscSummary { detail.summary }

    /// 没有任何完整版地址，说明只能试听。
    private var isPreviewOnly: Bool {
        !detail.streams.isEmpty && detail.streams.values.allSatisfy(DizzyURL.isPreviewStream)
    }

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 24) {
                header
                actions
                if !summary.tags.isEmpty {
                    tags
                }
                trackList
                if !detail.description.isEmpty {
                    ExpandableText(title: "介绍", text: detail.description)
                }
                if !detail.credits.isEmpty {
                    ExpandableText(title: "曲目与制作人员", text: detail.credits)
                }
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 16)
        }
    }

    private var header: some View {
        VStack(spacing: 10) {
            ArtworkImage(url: summary.coverURL, cornerRadius: 14)
                .frame(maxWidth: 280)
                .shadow(color: .black.opacity(0.4), radius: 16, y: 8)
                .padding(.bottom, 8)
            Text(summary.title)
                .font(.title2.bold())
                .foregroundStyle(DizzyPalette.text)
                .multilineTextAlignment(.center)
                .textSelection(.enabled)
            if let label = summary.labelName {
                NavigationLink(value: AppRoute.label(name: label)) {
                    Text(label)
                        .font(.headline)
                        .foregroundStyle(DizzyPalette.accent)
                }
                .buttonStyle(.plain)
            }
            HStack(spacing: 12) {
                if let price = summary.price {
                    PriceText(price: price)
                }
                if let date = detail.releaseDate {
                    Text(date)
                }
                if let likes = summary.likes, likes > 0 {
                    // 网页把点赞数乘以 2，显示为 dB。
                    Label("\(likes * 2) dB", systemImage: "heart.fill")
                }
                if summary.isHiRes {
                    Text("Hi-Res")
                }
            }
            .font(.caption)
            .foregroundStyle(DizzyPalette.mutedText)
        }
        .frame(maxWidth: .infinity)
    }

    private var actions: some View {
        VStack(spacing: 8) {
            HStack(spacing: 12) {
                Button {
                    play(from: 0)
                } label: {
                    Label(isPreviewOnly ? "试听" : "播放", systemImage: "play.fill")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .disabled(tracks.isEmpty)
                Link(destination: DizzyURL.disc(summary.id)) {
                    Label("在网页中打开", systemImage: "safari")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
            }
            .controlSize(.large)
            if isPreviewOnly {
                Text("未购买时只能试听片段。购买和下载请在网页中进行。")
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
        VStack(alignment: .leading, spacing: 4) {
            SectionHeading(title: "曲目")
                .padding(.bottom, 6)
            ForEach(tracks.enumerated(), id: \.element.id) { index, track in
                Button {
                    play(from: index)
                } label: {
                    TrackRow(
                        track: track,
                        isPreview: detail.streams[track.number].map(DizzyURL.isPreviewStream) ?? false,
                        isCurrent: player.currentTrack?.id == track.id
                    )
                }
                .buttonStyle(.plain)
            }
        }
    }

    private func play(from index: Int) {
        player.play(tracks, startAt: index, streams: detail.streams)
    }
}

/// 曲目行：序号、标题、艺术家、时长，未购买时标注「试听」。
struct TrackRow: View {
    let track: Track
    let isPreview: Bool
    var isCurrent = false

    var body: some View {
        HStack(spacing: 12) {
            Group {
                if isCurrent {
                    Image(systemName: "speaker.wave.2.fill")
                        .foregroundStyle(DizzyPalette.accent)
                } else {
                    Text(track.number)
                        .foregroundStyle(DizzyPalette.mutedText)
                }
            }
            .font(.subheadline.monospacedDigit())
            .frame(width: 24)

            VStack(alignment: .leading, spacing: 2) {
                Text(track.title)
                    .font(.body)
                    .foregroundStyle(isCurrent ? DizzyPalette.accent : DizzyPalette.text)
                    .lineLimit(2)
                if !track.artists.isEmpty {
                    Text(track.artists)
                        .font(.caption)
                        .foregroundStyle(DizzyPalette.mutedText)
                        .lineLimit(1)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            if isPreview {
                Text("试听")
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(DizzyPalette.mutedText)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .overlay(Capsule().stroke(DizzyPalette.mutedText.opacity(0.6)))
            }
            if let duration = track.duration {
                Text(Duration.seconds(duration).formatted(.time(pattern: .minuteSecond)))
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(DizzyPalette.mutedText)
            }
        }
        .padding(.vertical, 8)
        .contentShape(.rect)
    }
}

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
