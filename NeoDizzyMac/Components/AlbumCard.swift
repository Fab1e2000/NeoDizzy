import AppKit
import Nuke
import SwiftUI

/// 网格里的一张专辑：圆角封面加轻微阴影，下方标题与副标题。
/// 悬停时与 Music 一样在封面左下角显示播放按钮、右下角显示更多操作。
struct AlbumCard<Menu: View>: View {
    let title: String
    var subtitle: String?
    var caption: String?
    var price: PriceTag?
    let coverURL: URL?
    var isHiRes = false
    let route: AppRoute
    var webURL: URL?
    var play: ((Bool) async throws -> Void)?
    @ViewBuilder var menu: Menu

    @State private var isHovering = false
    @State private var isStarting = false

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            NavigationLink(value: route) {
                ArtworkImage(url: coverURL, cornerRadius: 8, decodeSize: PageMetrics.cardArtworkSize)
                    .overlay {
                        RoundedRectangle(cornerRadius: 8)
                            .fill(.black.opacity(isHovering ? 0.14 : 0))
                            .strokeBorder(.primary.opacity(0.08), lineWidth: 0.5)
                    }
                    // 先合成再加阴影：缩放窗口时每张卡片只渲染一次阴影。
                    .compositingGroup()
                    .shadow(color: .black.opacity(0.18), radius: 3, y: 2)
                    .overlay(alignment: .topTrailing) {
                        if isHiRes {
                            Text("Hi-Res")
                                .font(.caption2.weight(.bold))
                                .padding(.horizontal, 5).padding(.vertical, 2)
                                .background(.black.opacity(0.55), in: .capsule)
                                .foregroundStyle(DizzyPalette.accent)
                                .padding(7)
                        }
                    }
            }
            .buttonStyle(.plain)
            .overlay(alignment: .bottomLeading) {
                if let play, isHovering || isStarting {
                    CardOverlayButton(systemImage: "play.fill", isBusy: isStarting) { start(play, shuffled: false) }
                        .accessibilityLabel("播放\(title)")
                }
            }
            .overlay(alignment: .bottomTrailing) {
                if isHovering {
                    SwiftUI.Menu {
                        menuItems
                    } label: {
                        CardOverlayIcon(systemImage: "ellipsis")
                    }
                    .menuStyle(.button)
                    .buttonStyle(.plain)
                    .menuIndicator(.hidden)
                    .fixedSize()
                    .padding(8)
                    .accessibilityLabel("\(title)的更多操作")
                }
            }

            NavigationLink(value: route) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(.cardTitle)
                        .lineLimit(1)
                    if let subtitle, !subtitle.isEmpty {
                        Text(subtitle)
                            .font(.cardSubtitle)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                    if let price {
                        PriceLabel(price: price)
                    }
                    if let caption, !caption.isEmpty {
                        Text(caption)
                            .font(.callout)
                            .foregroundStyle(.secondary)
                            .lineLimit(2)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(.rect)
            }
            .buttonStyle(.plain)
        }
        .onHover { isHovering = $0 }
        .contextMenu { menuItems }
        .accessibilityElement(children: .contain)
        // 只在悬停片刻后才按详情页尺寸预解码封面；切换页面时不再为每张卡片额外解码一份大图。
        .task(id: isHovering) {
            guard isHovering else { return }
            try? await Task.sleep(for: .milliseconds(300))
            guard !Task.isCancelled else { return }
            await prefetchHeroArtwork(coverURL)
        }
    }

    @ViewBuilder private var menuItems: some View {
        if let play {
            Button("播放", systemImage: "play") { start(play, shuffled: false) }
            Button("随机播放", systemImage: "shuffle") { start(play, shuffled: true) }
            Divider()
        }
        menu
        if let webURL {
            Link(destination: webURL) { Label("在浏览器中打开", systemImage: "safari") }
            Button("拷贝链接", systemImage: "link") {
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(webURL.absoluteString, forType: .string)
            }
        }
    }

    private func start(_ play: @escaping (Bool) async throws -> Void, shuffled: Bool) {
        guard !isStarting else { return }
        isStarting = true
        Task {
            defer { isStarting = false }
            do { try await play(shuffled) } catch { NSSound.beep() }
        }
    }
}

extension AlbumCard where Menu == EmptyView {
    init(title: String, subtitle: String? = nil, caption: String? = nil, price: PriceTag? = nil, coverURL: URL?,
         isHiRes: Bool = false, route: AppRoute, webURL: URL? = nil, play: ((Bool) async throws -> Void)? = nil) {
        self.init(title: title, subtitle: subtitle, caption: caption, price: price, coverURL: coverURL, isHiRes: isHiRes,
                  route: route, webURL: webURL, play: play, menu: { EmptyView() })
    }
}

/// 封面上的圆形按钮：半透明深色底、白色图标。
private struct CardOverlayButton: View {
    let systemImage: String
    var isBusy = false
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            if isBusy {
                ProgressView().controlSize(.small).tint(.white)
                    .frame(width: 30, height: 30)
                    .background(.black.opacity(0.5), in: .circle)
            } else {
                CardOverlayIcon(systemImage: systemImage)
            }
        }
        .buttonStyle(.plain)
        .padding(8)
    }
}

private struct CardOverlayIcon: View {
    let systemImage: String
    @State private var isHovering = false

    var body: some View {
        Image(systemName: systemImage)
            .font(.system(size: 13, weight: .bold))
            .foregroundStyle(.white)
            .frame(width: 30, height: 30)
            .background(.black.opacity(isHovering ? 0.7 : 0.5), in: .circle)
            .scaleEffect(isHovering ? 1.06 : 1)
            .onHover { isHovering = $0 }
            .animation(.snappy(duration: 0.15), value: isHovering)
    }
}

/// 专辑网格。
struct DiscGrid: View {
    let discs: [DiscSummary]
    var showsLabel = true
    var caption: (DiscSummary) -> String? = { _ in nil }
    @Environment(MacAppModel.self) private var model

    var body: some View {
        LazyVGrid(columns: PageMetrics.gridColumns, alignment: .leading, spacing: PageMetrics.gridSpacing) {
            ForEach(discs) { disc in
                DiscCard(disc: disc, showsLabel: showsLabel, caption: caption(disc))
            }
        }
    }
}

/// 一张站点专辑的卡片：社团、价格、Hi-Res，悬停播放会先取专辑详情。
struct DiscCard: View {
    let disc: DiscSummary
    var showsLabel = true
    var caption: String?
    @Environment(MacAppModel.self) private var model

    @State private var isHovering = false

    var body: some View {
        AlbumCard(title: disc.title, subtitle: showsLabel ? disc.labelName : nil, caption: caption,
                  price: disc.isOwned ? nil : disc.price, coverURL: disc.coverURL, isHiRes: disc.isHiRes,
                  route: .disc(id: disc.id), webURL: DizzyURL.disc(disc.id),
                  play: { shuffled in try await model.playAlbum(id: disc.id, shuffled: shuffled) }) {
            if let label = disc.labelName {
                Button("前往社团「\(label)」", systemImage: "music.mic") { model.navigation.open(.label(name: label)) }
                Divider()
            }
        }
        .onHover { isHovering = $0 }
        // 悬停片刻后预取专辑详情，点进专辑页时通常不必再等待加载。
        .task(id: isHovering) {
            guard isHovering else { return }
            try? await Task.sleep(for: .milliseconds(300))
            guard !Task.isCancelled else { return }
            DiscDetailPrefetcher.shared.prefetch(disc.id)
        }
    }
}

/// 专辑详情预取。结果只保留两分钟：详情里的播放地址带时间签名，会过期。
final class DiscDetailPrefetcher {
    static let shared = DiscDetailPrefetcher()
    private var tasks: [String: (task: Task<DiscDetail, Error>, date: Date)] = [:]

    func prefetch(_ id: String) {
        purge()
        guard tasks[id] == nil else { return }
        tasks[id] = (Task { try await DizzyAPI.shared.discDetail(id: id) }, .now)
    }

    /// 取出已开始的预取请求（只用一次）；没有预取时返回 nil，由调用方正常请求。
    func prefetched(_ id: String) -> (() async throws -> DiscDetail)? {
        purge()
        guard let entry = tasks.removeValue(forKey: id) else { return nil }
        return { try await entry.task.value }
    }

    private func purge() {
        tasks = tasks.filter { $0.value.date.timeIntervalSinceNow > -120 }
    }
}

/// pack 卡片。
struct PackCard: View {
    let pack: PackSummary

    var body: some View {
        AlbumCard(title: pack.title, subtitle: pack.labelName, price: pack.price.map(PriceTag.price),
                  coverURL: pack.coverURL, route: .pack(id: pack.id), webURL: DizzyURL.pack(pack.id))
    }
}

/// 以详情页尺寸预解码封面，进入专辑页时直接命中缓存。
func prefetchHeroArtwork(_ url: URL?) async {
    guard let url else { return }
    var request = ImageRequest(url: url)
    request.thumbnail = .init(size: AlbumArtworkSize.hero, contentMode: .aspectFill)
    request.priority = .low
    _ = try? await ImagePipeline.shared.image(for: request)
}

enum AlbumArtworkSize {
    static let hero = CGSize(width: 540, height: 540)
}
