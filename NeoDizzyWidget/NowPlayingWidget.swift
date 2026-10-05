import SwiftUI
import WidgetKit

@main
struct NeoDizzyWidgetBundle: WidgetBundle {
    var body: some Widget {
        NowPlayingCoverWidget()
    }
}

/// 小号方形小组件：铺满当前播放歌曲的封面，轻点打开 App。
struct NowPlayingCoverWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: NowPlayingWidgetData.widgetKind, provider: NowPlayingProvider()) { entry in
            NowPlayingCoverView(entry: entry)
        }
        .configurationDisplayName("正在播放")
        .description("显示当前播放歌曲的封面，轻点打开 NeoDizzy。")
        .supportedFamilies([.systemSmall])
        .contentMarginsDisabled()
    }
}

nonisolated struct NowPlayingEntry: TimelineEntry {
    let date: Date
    let snapshot: NowPlayingWidgetData.Snapshot?
    let artwork: UIImage?

    static func current() -> NowPlayingEntry {
        NowPlayingEntry(date: .now, snapshot: NowPlayingWidgetData.load(),
                        artwork: NowPlayingWidgetData.loadArtwork().flatMap(UIImage.init(data:)))
    }
}

/// 内容只在换歌时由主 App 通知刷新，时间线本身不安排更新。
nonisolated struct NowPlayingProvider: TimelineProvider {
    func placeholder(in context: Context) -> NowPlayingEntry {
        NowPlayingEntry(date: .now, snapshot: nil, artwork: nil)
    }

    func getSnapshot(in context: Context, completion: @escaping (NowPlayingEntry) -> Void) {
        completion(.current())
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<NowPlayingEntry>) -> Void) {
        completion(Timeline(entries: [.current()], policy: .never))
    }
}

struct NowPlayingCoverView: View {
    let entry: NowPlayingEntry

    var body: some View {
        content
            .containerBackground(for: .widget) {
                // DizzyLab 的深色底，与 App 启动画面一致。
                Color(red: 0x1A / 255, green: 0x1A / 255, blue: 0x1A / 255)
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(accessibilityText)
    }

    @ViewBuilder
    private var content: some View {
        if let artwork = entry.artwork {
            Image(uiImage: artwork)
                .resizable()
                .widgetAccentedRenderingMode(.accentedDesaturated)
                .scaledToFill()
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .clipped()
        } else {
            VStack(spacing: 8) {
                Image(systemName: "music.note")
                    .font(.system(size: 32, weight: .semibold))
                    .foregroundStyle(Color(red: 0xF0 / 255, green: 0xAD / 255, blue: 0x4E / 255))
                    .widgetAccentable()
                Text(entry.snapshot?.title ?? "未在播放")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(.white)
                    .multilineTextAlignment(.center)
                    .lineLimit(2)
            }
            .padding(14)
        }
    }

    private var accessibilityText: String {
        guard let snapshot = entry.snapshot else { return "NeoDizzy，未在播放" }
        return "正在播放：\(snapshot.title)，\(snapshot.artists)"
    }
}

#Preview(as: .systemSmall) {
    NowPlayingCoverWidget()
} timeline: {
    NowPlayingEntry(date: .now, snapshot: nil, artwork: nil)
}
