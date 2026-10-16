// Layout adapted from MeloX (GPLv3), StandardMusicCollectionDetailHero.
import Nuke
import CoreImage
import CoreImage.CIFilterBuiltins
import SwiftUI

struct AlbumHero<Subtitle: View, Actions: View>: View {
    let artworkURL: URL?
    let title: String
    let metadata: String
    var reservesTitleSpace = false
    var metadataIsPlaceholder = false
    var titleIsPlaceholder = false
    @ViewBuilder let subtitle: () -> Subtitle
    @ViewBuilder let actions: () -> Actions

    var body: some View {
        VStack(spacing: 0) {
            AlbumHeroArtwork(url: artworkURL)
                .containerRelativeFrame(.horizontal) { width, _ in min(width * 0.68, 300) }
                .shadow(color: .black.opacity(0.18), radius: 18, y: 10)
            Text(title)
                .redacted(reason: titleIsPlaceholder ? .placeholder : [])
                .accessibilityHidden(titleIsPlaceholder)
                .font(.title2.bold()).multilineTextAlignment(.center).lineLimit(2, reservesSpace: reservesTitleSpace)
                .padding(.top, 24).padding(.horizontal, 24)
            subtitle().font(.title3).lineLimit(1).padding(.top, 8)
            Text(metadata).font(.subheadline.weight(.medium)).foregroundStyle(.secondary)
                .redacted(reason: metadataIsPlaceholder ? .placeholder : [])
                .accessibilityHidden(metadataIsPlaceholder)
                .multilineTextAlignment(.center).lineLimit(1).padding(.top, 7)
            actions().padding(.top, 17)
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 26).padding(.bottom, 22)
    }
}

/// Detail artwork must be available on the first render, before LazyImage's onAppear.
/// Keep the previous image during URL changes and isolate it from backdrop animations.
private struct AlbumHeroArtwork: View {
    let url: URL?
    @State private var container: ImageContainer?

    init(url: URL?) {
        self.url = url
        _container = State(initialValue: url.flatMap {
            ImagePipeline.shared.cache[AlbumArtworkPreload.heroRequest(for: $0)]
        })
    }

    var body: some View {
        GeometryReader { proxy in
            Group {
                if let container {
                    platformImage(container)
                        .resizable().scaledToFill()
                } else {
                    DizzyPalette.artworkPlaceholder
                }
            }
            .frame(width: proxy.size.width, height: proxy.size.height)
            .clipped()
        }
        .aspectRatio(1, contentMode: .fit)
        .clipShape(.rect(cornerRadius: 12))
        .accessibilityHidden(true)
        .transaction { transaction in
            transaction.animation = nil
            transaction.disablesAnimations = true
        }
        .task(id: url) {
            guard let url else { return }
            let request = AlbumArtworkPreload.heroRequest(for: url)
            if let cached = ImagePipeline.shared.cache[request], !cached.isPreview {
                container = cached
                return
            }
            guard let image = try? await ImagePipeline.shared.image(for: request),
                  !Task.isCancelled else { return }
            container = ImageContainer(image: image)
        }
    }

    private func platformImage(_ container: ImageContainer) -> Image {
        #if canImport(UIKit)
        Image(uiImage: container.image)
        #else
        Image(nsImage: container.image)
        #endif
    }
}

// Adapted from MeloX MusicCollectionPrimaryActions (GPL-3.0).
struct AlbumPlaybackActions<Accessory: View>: View {
    let isEmpty: Bool
    var isPreview = false
    var isDownloaded = false
    let play: (Bool) -> Void
    @ViewBuilder var accessory: () -> Accessory
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        // 页面内容里的普通按钮，不用液态玻璃：玻璃只留给浮在内容之上的控件。
        HStack(spacing: 14) {
            Button { play(true) } label: {
                Image(systemName: "shuffle")
                    .font(.title2.weight(.semibold))
                    .frame(width: 30, height: 30)
            }
            .buttonStyle(.bordered)
            .buttonBorderShape(.circle)
            .controlSize(.large)
            .disabled(isEmpty)
            .accessibilityLabel(isPreview ? "随机试听" : "随机播放")

            Button { play(false) } label: {
                Label(isPreview ? "试听" : "播放", systemImage: "play.fill")
                    .font(.title3.bold())
                    .frame(minWidth: 116)
            }
            .buttonStyle(.borderedProminent)
            .buttonBorderShape(.capsule)
            .controlSize(.large)
            .tint(colorScheme == .dark ? Color.white : .black)
            .foregroundStyle(colorScheme == .dark ? Color.black : .white)
            .disabled(isEmpty)

            accessory()
                .buttonStyle(.bordered)
                .buttonBorderShape(.circle)
                .controlSize(.large)
        }
        .tint(DizzyPalette.text)
    }
}

extension AlbumPlaybackActions where Accessory == EmptyView {
    init(isEmpty: Bool, isPreview: Bool = false, play: @escaping (Bool) -> Void) {
        self.isEmpty = isEmpty
        self.isPreview = isPreview
        self.play = play
        self.accessory = { EmptyView() }
    }
}

// Adapted from MeloX AlbumDetailView / AlbumDetailContent / MusicCollectionArtworkBackdrop
// and ArtworkAccentColorProvider (GPL-3.0).
/// 与 MeloX 一致：平均取色调成深浅底色，叠加离线模糊封面和渐变。
struct AlbumDetailScrollView<Content: View>: View {
    let artworkURL: URL?
    @ViewBuilder var content: Content
    @State private var appearance: AlbumBackdropModel
    @Environment(\.colorScheme) private var systemColorScheme
    @Environment(\.accessibilityReduceMotion) private var accessibilityReduceMotion

    init(artworkURL: URL?, @ViewBuilder content: () -> Content) {
        self.artworkURL = artworkURL
        self.content = content()
        // 从缓存里取到时第一帧就是封面色，推入页面不闪底色。
        _appearance = State(initialValue: AlbumBackdropModel(url: artworkURL))
    }

    private var backdrop: AlbumBackdrop? { appearance.backdrop }
    private var colorScheme: ColorScheme { backdrop?.colorScheme ?? systemColorScheme }

    var body: some View {
        ZStack {
            AlbumArtworkBackground(backdrop: backdrop)
            ScrollView { content }
                .scrollIndicators(.hidden)
        }
        .environment(\.colorScheme, colorScheme)
        // 与 MeloX 的专辑操作一致：控件随页面明暗配色，不继承全局主题色。
        .tint(.primary)
        // 表单的底色由系统按 App 外观决定，弹出的内容要换回这个外观，见 restoringAppColorScheme()。
        .environment(\.appColorScheme, systemColorScheme)
        .toolbarColorScheme(backdrop?.colorScheme, for: .navigationBar, .tabBar)
        .task(id: artworkURL) {
            await appearance.load(artworkURL, reduceMotion: accessibilityReduceMotion)
        }
    }
}

/// Keep background state and async loading independent of the generic content tree.
/// Cache misses retain the displayed image, and cancellation prevents stale publication.
@Observable
private final class AlbumBackdropModel {
    private(set) var backdrop: AlbumBackdrop?

    init(url: URL?) {
        backdrop = url.flatMap { AlbumBackdropCache.shared.backdrop(for: $0) }
    }

    func load(_ url: URL?, reduceMotion: Bool) async {
        guard let url, !Task.isCancelled else { return }
        let deadline = ContinuousClock.now.advanced(by: .milliseconds(350))
        let loaded = await AlbumBackdropProvider.shared.backdrop(for: url)
        guard !Task.isCancelled, let loaded,
              backdrop?.alreadyDisplays(loaded) != true else { return }
        do { try await Task.sleep(until: deadline, clock: .continuous) } catch { return }
        guard !Task.isCancelled else { return }
        withAnimation(reduceMotion ? nil : .easeOut(duration: 0.18)) { backdrop = loaded }
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
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        GeometryReader { proxy in
            ZStack {
                if let backdrop {
                    Color(red: backdrop.backgroundRGB.x, green: backdrop.backgroundRGB.y, blue: backdrop.backgroundRGB.z)
                    if let image = backdrop.blurredImage {
                        Image(decorative: image, scale: 1)
                            .resizable().scaledToFill()
                            .frame(width: proxy.size.width, height: proxy.size.height)
                            .opacity(0.22)
                            .transition(.opacity)
                    }
                } else {
                    Color(white: colorScheme == .dark ? 0.16 : 0.88)
                }
                LinearGradient(colors: overlayColors, startPoint: .top, endPoint: .bottom)
            }
            .frame(width: proxy.size.width, height: proxy.size.height)
            .clipped()
        }
        .ignoresSafeArea()
        .accessibilityHidden(true)
    }

    private var overlayColors: [Color] {
        let dark = backdrop?.prefersDarkAppearance ?? (colorScheme == .dark)
        return dark
            ? [.black.opacity(0.08), .black.opacity(0.24), .black.opacity(0.40)]
            : [.white.opacity(0.06), .white.opacity(0.16), .white.opacity(0.30)]
    }
}

// Pass an immutable reference across async boundaries instead of an over-aligned
// SIMD value payload, which corrupts task teardown in the optimized lifecycle test.
nonisolated final class AlbumBackdrop: Equatable, Sendable {
    let averageRGB: SIMD3<Double>
    let blurredImage: CGImage?

    init(averageRGB: SIMD3<Double>, blurredImage: CGImage? = nil) {
        self.averageRGB = averageRGB
        self.blurredImage = blurredImage
    }

    // MeloX uses weighted sRGB here, without converting to linear-light values.
    var prefersDarkAppearance: Bool {
        averageRGB.x * 0.2126 + averageRGB.y * 0.7152 + averageRGB.z * 0.0722 < 0.52
    }
    var colorScheme: ColorScheme { prefersDarkAppearance ? .dark : .light }
    var backgroundRGB: SIMD3<Double> {
        let color = prefersDarkAppearance
            ? averageRGB * 0.38 + SIMD3<Double>(repeating: 0.055) * 0.62
            : averageRGB * 0.30 + SIMD3<Double>(repeating: 0.94) * 0.70
        return color.clamped(lowerBound: .zero, upperBound: .one)
    }
    static func == (lhs: AlbumBackdrop, rhs: AlbumBackdrop) -> Bool {
        lhs.averageRGB == rhs.averageRGB && lhs.blurredImage === rhs.blurredImage
    }

    /// Like MeloX, skip a second transition when the palette and backdrop are already present.
    /// Re-decoding the same cover can produce a different CGImage instance.
    func alreadyDisplays(_ other: AlbumBackdrop) -> Bool {
        averageRGB == other.averageRGB && (blurredImage != nil || other.blurredImage == nil)
    }
}

/// Prepare color and blur off the main actor; navigation reuses the same cached assets.
private actor AlbumBackdropProvider {
    static let shared = AlbumBackdropProvider()
    private let context = CIContext(options: [.cacheIntermediates: false])
    private let colorSpace = CGColorSpace(name: CGColorSpace.sRGB)!

    func backdrop(for url: URL) async -> AlbumBackdrop? {
        if let cached = AlbumBackdropCache.shared.backdrop(for: url) { return cached }
        // Same source as MeloX: original bytes with EXIF orientation, Lanczos-scaled to at most 160 px.
        guard let (data, _) = try? await ImagePipeline.shared.data(for: ImageRequest(url: Self.paletteURL(for: url))),
              let image = CIImage(data: data, options: [.applyOrientationProperty: true]),
              !Task.isCancelled else { return nil }
        if let cached = AlbumBackdropCache.shared.backdrop(for: url) { return cached }
        let source = Self.downsampled(image)
        let extent = source.extent.integral
        guard !extent.isEmpty, !extent.isInfinite else { return nil }
        let average = CIFilter.areaAverage()
        average.inputImage = source
        average.extent = source.extent
        guard let output = average.outputImage else { return nil }
        var pixel = [UInt8](repeating: 0, count: 4)
        context.render(output, toBitmap: &pixel, rowBytes: 4,
                       bounds: CGRect(x: 0, y: 0, width: 1, height: 1), format: .RGBA8, colorSpace: colorSpace)
        let blur = CIFilter.gaussianBlur()
        blur.inputImage = source.clampedToExtent()
        blur.radius = 18
        let blurred = blur.outputImage.flatMap {
            context.createCGImage($0.cropped(to: extent), from: extent, format: .RGBA8, colorSpace: colorSpace)
        }
        let backdrop = AlbumBackdrop(
            averageRGB: SIMD3(Double(pixel[0]), Double(pixel[1]), Double(pixel[2])) / 255,
            blurredImage: blurred
        )
        AlbumBackdropCache.shared.insert(backdrop, for: url)
        return backdrop
    }

    /// NetEase covers are requested at 160×160, as MeloX does.
    nonisolated static func paletteURL(for url: URL) -> URL {
        guard url.host?.hasSuffix(".music.126.net") == true,
              var components = URLComponents(url: url, resolvingAgainstBaseURL: false) else { return url }
        var items = components.queryItems ?? []
        items.removeAll { $0.name.caseInsensitiveCompare("param") == .orderedSame }
        items.append(URLQueryItem(name: "param", value: "160y160"))
        components.queryItems = items
        return components.url ?? url
    }

    private static func downsampled(_ image: CIImage) -> CIImage {
        let maximumDimension = max(image.extent.width, image.extent.height)
        guard maximumDimension > 160 else { return image }
        let filter = CIFilter.lanczosScaleTransform()
        filter.inputImage = image
        filter.scale = Float(160 / maximumDimension)
        filter.aspectRatio = 1
        return filter.outputImage ?? image
    }
}

// Adapted from upstream MeloX Features/Playlist/PlaylistTrackList.swift (GPL-3.0).
// Album rows use this layout rather than MeloX's general-purpose TrackRowView.
struct AlbumRowAction: Identifiable {
    let id: String
    let title: String
    let systemImage: String
    var disabled = false
    let perform: () -> Void
}

struct AlbumTrackRow: View {
    @State private var songActions = SongActionPresentation()
    let track: Track
    var displayNumber: String? = nil
    var isPreview = false
    var isDownloaded = false
    var editTags: (() -> Void)?
    var additionalActions: [AlbumRowAction] = []
    /// 搜索结果用的紧凑行：小封面代替序号，歌名后跟歌手，不额外缩进。
    var compact = false
    let play: () -> Void
    @Environment(PlayerStore.self) private var player

    private var isCurrent: Bool { player.currentTrack?.id == track.id }

    var body: some View {
        HStack(spacing: 4) {
            playbackButton
            if isDownloaded { Image(systemName: "checkmark.circle.fill").font(.caption).foregroundStyle(.secondary).accessibilityLabel("已下载") }
            if isPreview {
                Text("试听").font(.caption2).foregroundStyle(.secondary)
            }
            Menu {
                Button(action: primaryAction) {
                    Label(isCurrent && player.isPlaying ? "暂停" : "播放", systemImage: isCurrent && player.isPlaying ? "pause.fill" : "play.fill")
                }
                SongLibraryActions(track: track, presentation: songActions)
                if let editTags {
                    Button("编辑音乐标签", systemImage: "pencil", action: editTags)
                }
                ForEach(additionalActions) { action in
                    Button(action.title, systemImage: action.systemImage, action: action.perform).disabled(action.disabled)
                }
            } label: {
                Image(systemName: "ellipsis")
                    .font(.body.weight(.semibold))
                    .frame(width: 42, height: 44)
                    .contentShape(.rect)
            }
            .accessibilityLabel("\(track.title)的更多操作")
        }
        .modifier(SongActionPresentationModifier(track: track, presentation: songActions))
        .padding(.leading, compact ? 0 : 20)
        .padding(.trailing, compact ? 0 : 8)
        // 与 MeloX 相同：44pt 的更多按钮上下再各留 11pt，每行 66pt；紧凑行 58pt。
        .padding(.vertical, compact ? 7 : 11)
        .overlay(alignment: .bottom) {
            // Divider 在 HStack 的 overlay 里会变成竖线，这里画一条横线。
            if compact { Rectangle().fill(Color(uiColor: .separator)).frame(height: 0.5).padding(.leading, 50) }
        }
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
                if compact {
                    HStack(alignment: .firstTextBaseline, spacing: 6) {
                        Text(track.title).font(.body).lineLimit(1).layoutPriority(1)
                        Text(track.artists).font(.subheadline).foregroundStyle(.secondary).lineLimit(1)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                } else {
                    Text(track.title)
                        .font(.body)
                        .lineLimit(2)
                        .multilineTextAlignment(.leading)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(track.title)，\(track.artists)")
        .accessibilityValue(isCurrent ? "当前播放" : "")
    }

    @ViewBuilder private var leadingContent: some View {
        if compact {
            ArtworkImage(url: track.coverURL, cornerRadius: 5)
                .frame(width: 38, height: 38)
                .overlay {
                    if isCurrent {
                        RoundedRectangle(cornerRadius: 5).fill(.black.opacity(0.35))
                        if player.isLoading {
                            ProgressView().controlSize(.mini).tint(.white)
                        } else {
                            Image(systemName: player.isPlaying ? "pause.fill" : "play.fill")
                                .font(.caption.weight(.bold)).foregroundStyle(.white)
                        }
                    }
                }
                .accessibilityHidden(true)
        } else if isCurrent {
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
            Text(displayNumber ?? track.number)
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
    private init() { cache.countLimit = 80; cache.totalCostLimit = 12 * 1_024 * 1_024 }
    func backdrop(for url: URL) -> AlbumBackdrop? { cache.object(forKey: url as NSURL)?.backdrop }
    func insert(_ backdrop: AlbumBackdrop, for url: URL) {
        let cost = backdrop.blurredImage.map { $0.bytesPerRow * $0.height } ?? 0
        cache.setObject(Box(backdrop), forKey: url as NSURL, cost: cost)
    }
}

enum AlbumArtworkPreload {
    // Match the detail hero request so Nuke reuses the decoded image, not just file data.
    static let heroSize = CGSize(width: 300, height: 300)

    static func heroRequest(for url: URL) -> ImageRequest {
        var request = ImageRequest(url: url)
        request.thumbnail = .init(size: heroSize, contentMode: .aspectFill)
        return request
    }
}

extension AlbumArtworkPreload {
    static func prepare(_ url: URL) async {
        async let backdrop = AlbumBackdropProvider.shared.backdrop(for: url)
        var request = heroRequest(for: url)
        request.priority = .low
        _ = try? await ImagePipeline.shared.image(for: request)
        _ = await backdrop
        guard !Task.isCancelled else { return }
        // Match ArtworkImage's common phone-grid and avatar decode buckets too.
        request.thumbnail = .init(size: CGSize(width: 256, height: 256), contentMode: .aspectFill)
        _ = try? await ImagePipeline.shared.image(for: request)
        guard !Task.isCancelled else { return }
        request.thumbnail = .init(size: CGSize(width: 128, height: 128), contentMode: .aspectFit)
        _ = try? await ImagePipeline.shared.image(for: request)
    }

    /// Only warm the first screen; visible cards continue prefetching as the user scrolls.
    static func prepareFirstScreen(_ urls: [URL]) async {
        let urls = Array(Set(urls.prefix(12)))
        await withTaskGroup(of: Void.self) { group in
            var iterator = urls.makeIterator()
            for _ in 0..<3 {
                if let url = iterator.next() { group.addTask { await prepare(url) } }
            }
            for await _ in group {
                guard !Task.isCancelled else { group.cancelAll(); return }
                if let url = iterator.next() { group.addTask { await prepare(url) } }
            }
        }
    }
}

extension View {
    func prefetchAlbumArtwork(url: URL?) -> some View {
        task(id: url) {
            guard let url else { return }
            await AlbumArtworkPreload.prepare(url)
        }
    }
}

// Adapted from MeloX ExpandablePlaylistDescription (GPL-3.0).
struct AlbumDescriptionExcerpt: View {
    let text: String

    // 简介全文直接展开，不折叠。
    var body: some View {
        Text(text)
            .font(.body).foregroundStyle(.secondary)
            .multilineTextAlignment(.leading)
            .textSelection(.enabled)
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity, alignment: .leading)
    }
}
