// Layout adapted from MeloX (GPLv3), StandardMusicCollectionDetailHero.
import Nuke
import CoreImage
import SwiftUI

struct AlbumHero<Subtitle: View, Actions: View>: View {
    let artworkURL: URL?
    let title: String
    let metadata: String
    @ViewBuilder let subtitle: () -> Subtitle
    @ViewBuilder let actions: () -> Actions

    var body: some View {
        VStack(spacing: 0) {
            ArtworkImage(url: artworkURL, cornerRadius: 12, decodeSize: AlbumArtworkPreload.heroSize)
                .containerRelativeFrame(.horizontal) { width, _ in min(width * 0.68, 300) }
                .shadow(color: .black.opacity(0.18), radius: 18, y: 10)
            Text(title)
                .font(.title2.bold()).multilineTextAlignment(.center).lineLimit(2)
                .padding(.top, 24).padding(.horizontal, 24)
            subtitle().font(.title3).lineLimit(1).padding(.top, 8)
            Text(metadata).font(.subheadline.weight(.medium)).foregroundStyle(.secondary)
                .multilineTextAlignment(.center).padding(.top, 7)
            actions().padding(.top, 17)
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 24).padding(.bottom, 22)
    }
}

/// 两个等宽的按钮，底色和文字都用主题色。按钮在页面内容里，不用玻璃材质：
/// 玻璃留给浮在内容上方的导航栏和标签栏。其他操作（网页、分享、批量编辑）放在导航栏里。
struct AlbumPlaybackActions: View {
    let isEmpty: Bool
    var isPreview = false
    let play: (Bool) -> Void

    var body: some View {
        HStack(spacing: 12) {
            Button { play(false) } label: {
                Label(isPreview ? "试听" : "播放", systemImage: "play.fill")
                    .frame(maxWidth: .infinity)
            }
            Button { play(true) } label: {
                Label(isPreview ? "随机试听" : "随机播放", systemImage: "shuffle")
                    .frame(maxWidth: .infinity)
            }
        }
        .font(.headline)
        .buttonStyle(.bordered)
        .buttonBorderShape(.capsule)
        .controlSize(.large)
        .tint(DizzyPalette.accent)
        .disabled(isEmpty)
    }
}

// Adapted from MeloX AlbumDetailView / AlbumDetailContent / MusicCollectionArtworkBackdrop
// and ArtworkAccentColorProvider (GPL-3.0).
/// 专辑页：背景直接用封面边缘的主色，不改写；再叠一层可调的黑或白遮罩。
/// 与 Apple Music 相同，页面深浅跟着背景色走：深色背景配白字，浅色背景配黑字。
struct AlbumDetailScrollView<Content: View>: View {
    let artworkURL: URL?
    @ViewBuilder var content: Content
    @State private var backdrop: AlbumBackdrop?
    @Environment(\.colorScheme) private var systemColorScheme
    @Environment(\.accessibilityReduceMotion) private var accessibilityReduceMotion

    init(artworkURL: URL?, @ViewBuilder content: () -> Content) {
        self.artworkURL = artworkURL
        self.content = content()
        // 从缓存里取到时第一帧就是封面色，推入页面不闪底色。
        _backdrop = State(initialValue: artworkURL.flatMap { AlbumBackdropCache.shared.backdrop(for: $0) })
    }

    private var colorScheme: ColorScheme { backdrop?.colorScheme ?? systemColorScheme }

    var body: some View {
        ZStack {
            AlbumArtworkBackground(backdrop: backdrop)
            ScrollView { content }
                .scrollIndicators(.hidden)
        }
        .environment(\.colorScheme, colorScheme)
        // 表单的底色由系统按 App 外观决定，弹出的内容要换回这个外观，见 restoringAppColorScheme()。
        .environment(\.appColorScheme, systemColorScheme)
        .toolbarColorScheme(backdrop?.colorScheme, for: .navigationBar, .tabBar)
        .task(id: artworkURL) {
            guard let artworkURL else { return }
            let loaded = await AlbumBackdropProvider.shared.backdrop(for: artworkURL)
            guard !Task.isCancelled, let loaded, loaded != backdrop else { return }
            withAnimation(accessibilityReduceMotion ? nil : .easeOut(duration: 0.18)) { backdrop = loaded }
        }
    }
}

extension EnvironmentValues {
    /// 专辑页按背景色改了深浅外观时，App 本来的外观。
    @Entry var appColorScheme: ColorScheme?
}

extension View {
    /// 用在专辑页里弹出的表单内容上。表单继承了页面按背景色改过的深浅外观，
    /// 底色却跟着 App 外观走，不换回来会出现白底白字。
    func restoringAppColorScheme() -> some View { modifier(RestoreAppColorScheme()) }
}

private struct RestoreAppColorScheme: ViewModifier {
    @Environment(\.appColorScheme) private var appColorScheme
    @Environment(\.colorScheme) private var colorScheme

    func body(content: Content) -> some View {
        content.environment(\.colorScheme, appColorScheme ?? colorScheme)
    }
}

private struct AlbumArtworkBackground: View {
    let backdrop: AlbumBackdrop?

    var body: some View {
        ZStack {
            if let backdrop {
                Color(red: backdrop.edgeRGB.x, green: backdrop.edgeRGB.y, blue: backdrop.edgeRGB.z)
                // 深色背景叠一层黑，浅色背景叠一层白，浓度在「外观与主题」里调，默认 5%。
                (backdrop.prefersDarkAppearance ? Color.black : Color.white)
                    .opacity(Double(AppearanceSettings.shared.albumDimming) / 100)
            } else {
                DizzyPalette.background
            }
        }
        .ignoresSafeArea()
        .accessibilityHidden(true)
    }
}

/// 封面取色结果：边缘主色，以及它配白字还是黑字。
nonisolated struct AlbumBackdrop: Equatable, Sendable {
    let edgeRGB: SIMD3<Double>

    /// 按对比度在白字、黑字之间选：白字更清楚就用深色外观。与主题色上文字颜色的算法相同。
    var prefersDarkAppearance: Bool { Self.relativeLuminance(edgeRGB) <= 0.179 }
    var colorScheme: ColorScheme { prefersDarkAppearance ? .dark : .light }

    /// WCAG 相对亮度：先把 sRGB 换回线性值再加权。
    static func relativeLuminance(_ color: SIMD3<Double>) -> Double {
        func linear(_ value: Double) -> Double {
            value <= 0.04045 ? value / 12.92 : pow((value + 0.055) / 1.055, 2.4)
        }
        return 0.2126 * linear(color.x) + 0.7152 * linear(color.y) + 0.0722 * linear(color.z)
    }

    /// 取封面外圈像素里占比最多的颜色。颜色按每通道 8 档分组，组和相邻的组一起计数，
    /// 渐变或噪点不会被拆散；外圈颜色太杂、最多的一组不到四分之一时，改取整张封面的主色。
    /// `pixels` 是 RGBA8，透明像素不计。
    static func edgeColor(pixels: [UInt8], width: Int, height: Int) -> SIMD3<Double> {
        let band = max(2, Int((Double(min(width, height)) * 0.08).rounded()))
        let edge = dominantColor(pixels: pixels, width: width, height: height) { x, y in
            x < band || y < band || x >= width - band || y >= height - band
        }
        if let edge, edge.share >= 0.25 { return edge.color }
        return dominantColor(pixels: pixels, width: width, height: height) { _, _ in true }?.color
            ?? edge?.color ?? SIMD3(repeating: 0.16)
    }

    private static func dominantColor(pixels: [UInt8], width: Int, height: Int,
                                      include: (Int, Int) -> Bool) -> (color: SIMD3<Double>, share: Double)? {
        var counts = [Double](repeating: 0, count: 512)
        var sums = [SIMD3<Double>](repeating: .zero, count: 512)
        var total = 0.0
        for y in 0..<height {
            for x in 0..<width where include(x, y) {
                let index = (y * width + x) * 4
                guard pixels[index + 3] >= 128 else { continue }
                let color = unpremultiplied(pixels, at: index)
                let bin = SIMD3<Int>((color * 7.999).rounded(.down))
                let key = bin.x << 6 | bin.y << 3 | bin.z
                counts[key] += 1
                sums[key] += color
                total += 1
            }
        }
        guard total > 0 else { return nil }
        var best: (count: Double, sum: SIMD3<Double>) = (0, .zero)
        for key in 0..<512 where counts[key] > 0 {
            var count = 0.0, sum = SIMD3<Double>.zero
            let r = key >> 6, g = key >> 3 & 7, b = key & 7
            for nr in max(0, r - 1)...min(7, r + 1) {
                for ng in max(0, g - 1)...min(7, g + 1) {
                    for nb in max(0, b - 1)...min(7, b + 1) {
                        let neighbor = nr << 6 | ng << 3 | nb
                        count += counts[neighbor]
                        sum += sums[neighbor]
                    }
                }
            }
            if count > best.count { best = (count, sum) }
        }
        return (best.sum / best.count, best.count / total)
    }

    private static func unpremultiplied(_ pixels: [UInt8], at index: Int) -> SIMD3<Double> {
        let alpha = Double(pixels[index + 3])
        let color = SIMD3(Double(pixels[index]), Double(pixels[index + 1]), Double(pixels[index + 2])) / alpha
        return color.clamped(lowerBound: .zero, upperBound: .one)
    }
}

/// 缩到 160 像素、居中裁成正方形后取边缘主色，结果按封面地址缓存。
private actor AlbumBackdropProvider {
    static let shared = AlbumBackdropProvider()
    private let context = CIContext(options: [.cacheIntermediates: false])
    private let colorSpace = CGColorSpace(name: CGColorSpace.sRGB)!

    func backdrop(for url: URL) async -> AlbumBackdrop? {
        if let cached = AlbumBackdropCache.shared.backdrop(for: url) { return cached }
        var request = ImageRequest(url: url)
        request.thumbnail = .init(size: CGSize(width: 160, height: 160), unit: .pixels, contentMode: .aspectFill)
        guard let loaded = try? await ImagePipeline.shared.image(for: request),
              let source = CIImage(image: loaded), !Task.isCancelled else { return nil }
        if let cached = AlbumBackdropCache.shared.backdrop(for: url) { return cached }
        let extent = source.extent.integral
        guard !extent.isEmpty, !extent.isInfinite else { return nil }
        // 缩略图只按短边缩放，不是正方形的封面会比 160 宽或高。页面上的封面是居中裁成正方形的，
        // 取色也只看这个正方形，否则会取到被裁掉的那一截。
        let side = min(extent.width, extent.height)
        let square = CGRect(x: extent.midX - side / 2, y: extent.midY - side / 2, width: side, height: side).integral
        let width = Int(square.width), height = Int(square.height)
        var pixels = [UInt8](repeating: 0, count: width * height * 4)
        context.render(source, toBitmap: &pixels, rowBytes: width * 4, bounds: square,
                       format: .RGBA8, colorSpace: colorSpace)
        let backdrop = AlbumBackdrop(edgeRGB: AlbumBackdrop.edgeColor(pixels: pixels, width: width, height: height))
        AlbumBackdropCache.shared.insert(backdrop, for: url)
        return backdrop
    }
}

// Adapted from upstream MeloX Features/Playlist/PlaylistTrackList.swift (GPL-3.0).
// Album rows use this layout rather than MeloX's general-purpose TrackRowView.
struct AlbumTrackRow: View {
    let track: Track
    var isPreview = false
    var editTags: (() -> Void)?
    let play: () -> Void
    @Environment(PlayerStore.self) private var player

    private var isCurrent: Bool { player.currentTrack?.id == track.id }

    var body: some View {
        HStack(spacing: 4) {
            playbackButton
            if isPreview {
                Text("试听").font(.caption2).foregroundStyle(.secondary)
            }
            Menu {
                Button(action: primaryAction) {
                    Label(isCurrent && player.isPlaying ? "暂停" : "播放", systemImage: isCurrent && player.isPlaying ? "pause.fill" : "play.fill")
                }
                if let editTags {
                    Button("编辑音乐标签", systemImage: "pencil", action: editTags)
                }
            } label: {
                Image(systemName: "ellipsis")
                    .font(.body.weight(.semibold))
                    .frame(width: 42, height: 44)
                    .contentShape(.rect)
            }
            .accessibilityLabel("\(track.title)的更多操作")
        }
        .padding(.leading, 20)
        .padding(.trailing, 8)
        // 与 MeloX 相同：44pt 的更多按钮上下再各留 11pt，每行 66pt。
        .padding(.vertical, 11)
        .foregroundStyle(.primary)
        .tint(.primary)
        .background(isCurrent ? Color.primary.opacity(0.10) : .clear)
        .accessibilityElement(children: .contain)
    }

    @ViewBuilder private var playbackButton: some View {
        if let editTags {
            button.highPriorityGesture(LongPressGesture(minimumDuration: 0.5).onEnded { _ in editTags() })
                .accessibilityAction(named: "编辑音乐标签", editTags)
        } else {
            button
        }
    }

    private var button: some View {
        Button(action: primaryAction) {
            HStack(spacing: 12) {
                leadingContent
                Text(track.title)
                    .font(.body)
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(track.title)，\(track.artists)")
        .accessibilityValue(isCurrent ? "当前播放" : "")
    }

    @ViewBuilder private var leadingContent: some View {
        if isCurrent {
            ZStack {
                Circle().stroke(Color.primary.opacity(0.60), lineWidth: 1.5)
                if player.isLoading {
                    ProgressView().controlSize(.mini)
                } else {
                    Image(systemName: player.isPlaying ? "pause.fill" : "play.fill")
                        .font(.caption.weight(.bold))
                }
            }
            .frame(width: 32, height: 32)
            .frame(width: 40)
        } else {
            Text(track.number)
                .font(.title3)
                .foregroundStyle(.secondary)
                .monospacedDigit()
                .lineLimit(1)
                .minimumScaleFactor(0.8)
                .frame(width: 40, alignment: .center)
        }
    }

    private func primaryAction() {
        if isCurrent { player.togglePlayback() } else { play() }
    }
}


// NSCache is thread-safe; the view reads it synchronously while the actor inserts results.
private nonisolated final class AlbumBackdropCache: @unchecked Sendable {
    static let shared = AlbumBackdropCache()
    private final class Box { let backdrop: AlbumBackdrop; init(_ backdrop: AlbumBackdrop) { self.backdrop = backdrop } }
    private let cache = NSCache<NSURL, Box>()
    private init() { cache.countLimit = 500 }
    func backdrop(for url: URL) -> AlbumBackdrop? { cache.object(forKey: url as NSURL)?.backdrop }
    func insert(_ backdrop: AlbumBackdrop, for url: URL) { cache.setObject(Box(backdrop), forKey: url as NSURL) }
}

enum AlbumArtworkPreload {
    // Match the detail hero request so Nuke reuses the decoded image, not just file data.
    static let heroSize = CGSize(width: 300, height: 300)
}

extension View {
    func prefetchAlbumArtwork(url: URL?) -> some View {
        task(id: url) {
            guard let url else { return }
            async let backdrop = AlbumBackdropProvider.shared.backdrop(for: url)
            var request = ImageRequest(url: url)
            request.thumbnail = .init(size: AlbumArtworkPreload.heroSize, contentMode: .aspectFill)
            request.priority = .low
            _ = try? await ImagePipeline.shared.image(for: request)
            _ = await backdrop
        }
    }
}
