// Layout adapted from MeloX (GPLv3), StandardMusicCollectionDetailHero.
import Nuke
import CoreImage.CIFilterBuiltins
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

/// 与 Apple Music 专辑页相同：两个等宽的玻璃按钮，文字和图标用主题色。
/// 其他操作（网页、分享、批量编辑）放在导航栏里。
struct AlbumPlaybackActions: View {
    let isEmpty: Bool
    var isPreview = false
    let play: (Bool) -> Void

    var body: some View {
        GlassEffectContainer(spacing: 12) {
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
            .foregroundStyle(DizzyPalette.accent)
            .buttonStyle(.glass)
            .buttonBorderShape(.capsule)
            .controlSize(.large)
            .disabled(isEmpty)
        }
    }
}

// Adapted from MeloX AlbumDetailView / AlbumDetailContent / MusicCollectionArtworkBackdrop
// and ArtworkAccentColorProvider (GPL-3.0).
/// 专辑页：背景取封面的平均色，深色封面压暗、浅色封面提亮，再叠一层模糊封面；
/// 整页的深浅外观跟着封面走，文字和按钮在任何封面上都看得清。
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
        .toolbarColorScheme(backdrop?.colorScheme, for: .navigationBar, .tabBar)
        .task(id: artworkURL) {
            guard let artworkURL else { return }
            let loaded = await AlbumBackdropProvider.shared.backdrop(for: artworkURL)
            guard !Task.isCancelled, let loaded, loaded != backdrop else { return }
            withAnimation(accessibilityReduceMotion ? nil : .easeOut(duration: 0.18)) { backdrop = loaded }
        }
    }
}

private struct AlbumArtworkBackground: View {
    let backdrop: AlbumBackdrop?

    var body: some View {
        GeometryReader { proxy in
            ZStack {
                backdrop?.backgroundColor ?? DizzyPalette.background
                if let image = backdrop?.blurredImage {
                    Image(decorative: image, scale: 1)
                        .resizable()
                        .scaledToFill()
                        .frame(width: proxy.size.width, height: proxy.size.height)
                        .opacity(0.22)
                        .transition(.opacity)
                }
                LinearGradient(colors: overlayColors, startPoint: .top, endPoint: .bottom)
            }
            .frame(width: proxy.size.width, height: proxy.size.height)
            .clipped()
        }
        .ignoresSafeArea()
        .accessibilityHidden(true)
    }

    /// 深色页往下逐渐压暗，浅色页往下逐渐提亮，长列表底部依然清楚。
    private var overlayColors: [Color] {
        guard let backdrop else { return [.clear] }
        let tint: Color = backdrop.prefersDarkAppearance ? .black : .white
        return backdrop.prefersDarkAppearance
            ? [tint.opacity(0.08), tint.opacity(0.24), tint.opacity(0.40)]
            : [tint.opacity(0.06), tint.opacity(0.16), tint.opacity(0.30)]
    }
}

/// 封面取色结果：底色、深浅外观和预先模糊好的封面。
nonisolated struct AlbumBackdrop: Equatable, @unchecked Sendable {
    let backgroundRGB: SIMD3<Double>
    let prefersDarkAppearance: Bool
    let blurredImage: CGImage?

    var colorScheme: ColorScheme { prefersDarkAppearance ? .dark : .light }
    var backgroundColor: Color { Color(red: backgroundRGB.x, green: backgroundRGB.y, blue: backgroundRGB.z) }

    static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.backgroundRGB == rhs.backgroundRGB && lhs.prefersDarkAppearance == rhs.prefersDarkAppearance
            && lhs.blurredImage === rhs.blurredImage
    }

    /// 与 MeloX 相同：按平均色的亮度决定深浅，再把平均色混进接近黑或接近白的底色。
    static func palette(from source: SIMD3<Double>) -> (background: SIMD3<Double>, prefersDark: Bool) {
        let luminance = source.x * 0.2126 + source.y * 0.7152 + source.z * 0.0722
        let prefersDark = luminance < 0.52
        let background = prefersDark
            ? source * 0.38 + SIMD3<Double>(repeating: 0.055) * 0.62
            : source * 0.30 + SIMD3<Double>(repeating: 0.94) * 0.70
        return (background.clamped(lowerBound: .zero, upperBound: .one), prefersDark)
    }
}

/// 缩到 160 像素后取平均色、模糊，结果按封面地址缓存。模糊前先把边缘像素向外延伸，与上游一致。
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
        let palette = AlbumBackdrop.palette(from: averageColor(of: source, in: extent))
        let backdrop = AlbumBackdrop(backgroundRGB: palette.background, prefersDarkAppearance: palette.prefersDark,
                                     blurredImage: blurred(source, extent: extent))
        AlbumBackdropCache.shared.insert(backdrop, for: url)
        return backdrop
    }

    private func averageColor(of image: CIImage, in extent: CGRect) -> SIMD3<Double> {
        let filter = CIFilter.areaAverage()
        filter.inputImage = image
        filter.extent = extent
        guard let output = filter.outputImage else { return SIMD3(repeating: 0.16) }
        var pixel = [UInt8](repeating: 0, count: 4)
        context.render(output, toBitmap: &pixel, rowBytes: 4, bounds: CGRect(x: 0, y: 0, width: 1, height: 1),
                       format: .RGBA8, colorSpace: colorSpace)
        return SIMD3(Double(pixel[0]), Double(pixel[1]), Double(pixel[2])) / 255
    }

    private func blurred(_ image: CIImage, extent: CGRect) -> CGImage? {
        let filter = CIFilter.gaussianBlur()
        filter.inputImage = image.clampedToExtent()
        filter.radius = 18
        guard let output = filter.outputImage?.cropped(to: extent) else { return nil }
        return context.createCGImage(output, from: extent, format: .RGBA8, colorSpace: colorSpace)
    }
}

// Adapted from upstream MeloX Features/Playlist/PlaylistTrackList.swift (GPL-3.0).
// Album rows use this layout rather than MeloX's general-purpose TrackRowView.
struct AlbumTrackRow: View {
    let track: Track
    var isPreview = false
    /// 行与行之间的分隔线，从标题处开始，与系统列表一致；最后一行不画。
    var showsSeparator = true
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
        .padding(.vertical, 3)
        .foregroundStyle(.primary)
        .tint(.primary)
        .background(isCurrent ? Color.primary.opacity(0.10) : .clear)
        .overlay(alignment: .bottom) {
            if showsSeparator { Divider().padding(.leading, 72) }
        }
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
                .font(.body)
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
    private init() { cache.totalCostLimit = 8 * 1024 * 1024 }
    func backdrop(for url: URL) -> AlbumBackdrop? { cache.object(forKey: url as NSURL)?.backdrop }
    func insert(_ backdrop: AlbumBackdrop, for url: URL) {
        let cost = backdrop.blurredImage.map { $0.bytesPerRow * $0.height } ?? 0
        cache.setObject(Box(backdrop), forKey: url as NSURL, cost: cost)
    }
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
