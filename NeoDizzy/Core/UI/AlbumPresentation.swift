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
    /// 圆形按钮的实际宽度，量出来后用来算播放按钮的宽度。
    @State private var circleWidth: CGFloat = 50

    private var spacing: CGFloat { 14 }
    private var pageInset: CGFloat { 20 }

    var body: some View {
        // 页面内容里的普通按钮，不用液态玻璃：玻璃只留给浮在内容之上的控件。
        HStack(spacing: spacing) {
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
            .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { circleWidth = $0 }

            // 播放按钮固定为"一排四个按钮"时的宽度：按钮少的页面不再把它拉长，整排居中。
            Button { play(false) } label: {
                Label(isPreview ? "试听" : "播放", systemImage: "play.fill")
                    .font(.title3.bold())
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .buttonBorderShape(.capsule)
            .controlSize(.large)
            .tint(colorScheme == .dark ? Color.white : .black)
            .foregroundStyle(colorScheme == .dark ? Color.black : .white)
            .disabled(isEmpty)
            .containerRelativeFrame(.horizontal) { width, _ in
                max(width - 2 * pageInset - 3 * circleWidth - 3 * spacing, 72)
            }

            accessory()
                .buttonStyle(.bordered)
                .buttonBorderShape(.circle)
                .controlSize(.large)
        }
        .frame(maxWidth: .infinity)
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
/// 封面平均色混入白色，叠加低透明度模糊封面，始终使用浅色背景。
struct AlbumDetailScrollView<Content: View>: View {
    let artworkURL: URL?
    @ViewBuilder var content: Content
    @State private var appearance: AlbumBackdropModel

    init(artworkURL: URL?, @ViewBuilder content: () -> Content) {
        self.artworkURL = artworkURL
        self.content = content()
        // 从缓存里取到时第一帧就是封面色，推入页面不闪底色。
        _appearance = State(initialValue: AlbumBackdropModel(url: artworkURL))
    }

    private var backdrop: AlbumBackdrop? { appearance.backdrop }
    private var colorScheme: ColorScheme { .light }

    var body: some View {
        ZStack {
            AlbumArtworkBackground(backdrop: backdrop)
            ScrollView { content }
                .scrollIndicators(.hidden)
                .tint(.primary)
        }
        .environment(\.colorScheme, colorScheme)
        .environment(\.albumBackdrop, backdrop)
        // 专辑及其表单统一使用浅色，操作按钮保持中性色。
        .environment(\.appColorScheme, .light)
        .toolbarColorScheme(.light, for: .navigationBar)
        .task(id: artworkURL) {
            await appearance.load(artworkURL)
        }
    }
}

/// Keep background state and async loading independent of the generic content tree.
/// Cache misses retain the displayed image, and cancellation prevents stale publication.
@Observable
final class AlbumBackdropModel {
    private(set) var backdrop: AlbumBackdrop?

    init(url: URL?) {
        backdrop = url.flatMap { AlbumBackdropCache.shared.backdrop(for: $0) }
    }

    func load(_ url: URL?) async {
        guard let url, !Task.isCancelled else { return }
        let loaded = await AlbumBackdropProvider.shared.backdrop(for: url)
        guard !Task.isCancelled, let loaded,
              backdrop?.alreadyDisplays(loaded) != true else { return }
        // Prepared navigation already has the final background on its first frame.
        // Unknown artwork (e.g. recent songs) is applied as soon as it becomes available.
        var transaction = Transaction(animation: nil)
        transaction.disablesAnimations = true
        withTransaction(transaction) { backdrop = loaded }
    }
}

extension EnvironmentValues {
    /// 专辑页按背景色改了深浅外观时，App 本来的外观。
    @Entry var appColorScheme: ColorScheme?
    /// 阅读页沿用当前专辑已经显示的封面背景，不重新加载或恢复成全局底色。
    @Entry fileprivate var albumBackdrop: AlbumBackdrop?
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
                            .opacity(0.10)
                            .transition(.opacity)
                    }
                } else {
                    Color(white: 0.97)
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
        [.white.opacity(0.06), .white.opacity(0.16), .white.opacity(0.30)]
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

    /// White-based tint for every cover, including black or highly saturated art.
    var backgroundRGB: SIMD3<Double> {
        let color = averageRGB * 0.12 + SIMD3<Double>(repeating: 0.98) * 0.88
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
    nonisolated static func hasPreparedBackdrop(for url: URL) -> Bool {
        AlbumBackdropCache.shared.backdrop(for: url) != nil
    }

    static func prepareBackdrop(_ url: URL) async {
        _ = await AlbumBackdropProvider.shared.backdrop(for: url)
    }

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

/// A pending tap belongs to one card identity. Replaced/cancelled work cannot push a page later.
@Observable @MainActor
final class AlbumNavigationPreparation {
    struct Request: Hashable {
        let id = UUID()
        let route: AppRoute
        let artworkURL: URL
    }
    private(set) var request: Request?

    func begin(_ route: AppRoute, artworkURL: URL?,
               isReady: (URL) -> Bool = AlbumArtworkPreload.hasPreparedBackdrop) -> AppRoute? {
        guard request == nil else { return nil }
        guard let artworkURL, !isReady(artworkURL) else { return route }
        request = Request(route: route, artworkURL: artworkURL)
        return nil
    }

    func finish(_ pending: Request,
                prepare: (URL) async -> Void = AlbumArtworkPreload.prepareBackdrop) async -> AppRoute? {
        guard request == pending else { return nil }
        await prepare(pending.artworkURL)
        guard !Task.isCancelled, request == pending else { return nil }
        request = nil
        return pending.route
    }

    func cancel() { request = nil }
}

extension View {
    func preparedAlbumNavigation(_ preparation: AlbumNavigationPreparation) -> some View {
        modifier(PreparedAlbumNavigation(preparation: preparation))
    }
}

private struct PreparedAlbumNavigation: ViewModifier {
    let preparation: AlbumNavigationPreparation
    @Environment(\.openRoute) private var openRoute

    func body(content: Content) -> some View {
        content
            .task(id: preparation.request) {
                guard let pending = preparation.request else { return }
                if let route = await preparation.finish(pending) { openRoute(route) }
            }
            .onDisappear { preparation.cancel() }
    }
}

/// Keep a cold-cache tap on the current card until its destination can render the cover palette.
/// Cached cards navigate synchronously; failed artwork loads still allow opening the collection.
struct AlbumNavigationLink<Label: View>: View {
    let value: AppRoute
    let artworkURL: URL?
    /// A card may display a different artwork size/URL from the detail's preload.
    var sourceArtworkURL: URL? = nil
    /// Disable for text-only links; zoom labels contain one matching ArtworkImage.
    var zoomsFromArtwork = true
    @ViewBuilder var label: () -> Label
    @Environment(\.openRoute) private var openRoute
    @Environment(\.albumNavigationNamespace) private var transitionNamespace
    @State private var preparation = AlbumNavigationPreparation()
    @State private var transitionID = UUID()

    private var transitionSource: AlbumNavigationSource? {
        guard zoomsFromArtwork, let transitionNamespace,
              let sourceURL = sourceArtworkURL ?? artworkURL else { return nil }
        return AlbumNavigationSource(id: transitionID, namespace: transitionNamespace, artworkURL: sourceURL)
    }

    var body: some View {
        Button {
            if let route = preparation.begin(value, artworkURL: artworkURL) { navigate(to: route) }
        } label: {
            label()
                .overlay {
                    if preparation.request != nil {
                        ProgressView().padding(10).background(.regularMaterial, in: .circle)
                    }
                }
                .environment(\.albumNavigationSource, transitionSource)
        }
        .disabled(preparation.request != nil)
        .prefetchAlbumArtwork(url: artworkURL)
        .task(id: preparation.request) {
            guard let pending = preparation.request else { return }
            if let route = await preparation.finish(pending), value == pending.route, artworkURL == pending.artworkURL {
                navigate(to: route)
            }
        }
        .onChange(of: value) { preparation.cancel() }
        .onChange(of: artworkURL) { preparation.cancel() }
        .onDisappear { preparation.cancel() }
    }

    private func navigate(to route: AppRoute) {
        openRoute(transitionSource.map { route.zooming(from: $0.id) } ?? route)
    }
}

/// A source-neutral reading section; headings identify the sections within one description.
struct AlbumDescriptionSection: Identifiable {
    let title: String
    let text: String
    var id: String { title }
}

/// 三行摘要只在实际截断时显示「更多」；完整阅读保留段落和当前封面背景。
struct AlbumDescriptionExcerpt: View {
    let title: String
    let subtitle: String?
    let sections: [AlbumDescriptionSection]
    let accessibilityTitle: String
    @Environment(\.albumBackdrop) private var backdrop
    @Environment(\.colorScheme) private var colorScheme
    @State private var isPresented = false
    @State private var collapsedHeight: CGFloat = 0
    @State private var fullHeight: CGFloat = 0
    @State private var moreSize: CGSize = .zero
    private static let lineLimit = 3
    private static let fadeWidth: CGFloat = 32

    init(text: String, title: String, subtitle: String? = nil, accessibilityTitle: String = "介绍") {
        self.init(title: title, subtitle: subtitle,
                  sections: [.init(title: "介绍", text: text)], accessibilityTitle: accessibilityTitle)
    }

    init(title: String, subtitle: String? = nil, sections: [AlbumDescriptionSection], accessibilityTitle: String = "介绍") {
        self.title = title
        self.subtitle = subtitle
        self.sections = sections.filter { !$0.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
        self.accessibilityTitle = accessibilityTitle
    }

    private var excerpt: String {
        sections.map(\.text)
            .flatMap { $0.split(whereSeparator: \.isNewline) }
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
            .reduce(into: "") { result, line in
                // 中文行之间直接相连，西文行之间补一个空格。
                if let last = result.last, !Self.isWide(last), !Self.isWide(line.first!) { result += " " }
                result += line
            }
    }

    private var isTruncated: Bool { fullHeight > collapsedHeight + 1 }

    private static func isWide(_ character: Character) -> Bool {
        character.unicodeScalars.contains { scalar in
            switch scalar.value {
            case 0x2E80...0x9FFF, 0xAC00...0xD7AF, 0xF900...0xFAFF, 0xFE30...0xFE4F, 0xFF00...0xFFEF: true
            default: false
            }
        }
    }

    var body: some View {
        if !sections.isEmpty {
            Button { if isTruncated { isPresented = true } } label: { content }
                .buttonStyle(.plain)
                .allowsHitTesting(isTruncated)
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(accessibilityTitle)
                .accessibilityValue(excerpt)
                .accessibilityHint(isTruncated ? "显示完整介绍" : "")
                .accessibilityRemoveTraits(isTruncated ? [] : .isButton)
                .accessibilityAddTraits(isTruncated ? [] : .isStaticText)
                .sheet(isPresented: $isPresented) {
                    AlbumDescriptionSheet(title: title, subtitle: subtitle, sections: sections, backdrop: backdrop)
                        .preferredColorScheme(colorScheme)
                }
        }
    }

    private var content: some View {
        styled(Text(excerpt))
            .lineLimit(Self.lineLimit)
            .frame(maxWidth: .infinity, alignment: .leading)
            .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { collapsedHeight = $0 }
            .background {
                styled(Text(excerpt))
                    .fixedSize(horizontal: false, vertical: true)
                    .hidden()
                    .accessibilityHidden(true)
                    .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { fullHeight = $0 }
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
        text.font(.subheadline)
            .foregroundStyle(.secondary)
            .lineSpacing(2)
            .multilineTextAlignment(.leading)
    }

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

private struct AlbumDescriptionSheet: View {
    let title: String
    let subtitle: String?
    let sections: [AlbumDescriptionSection]
    let backdrop: AlbumBackdrop?
    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        NavigationStack {
            ZStack {
                AlbumArtworkBackground(backdrop: backdrop)
                ScrollView {
                    VStack(alignment: .leading, spacing: 28) {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(title).font(.title2.bold())
                            if let subtitle, !subtitle.isEmpty {
                                Text(subtitle).font(.title3).foregroundStyle(.secondary)
                            }
                        }
                        ForEach(sections) { section in
                            VStack(alignment: .leading, spacing: 8) {
                                Text(section.title).font(.headline).accessibilityAddTraits(.isHeader)
                                Text(section.text.replacing(#/\n\s*\n\s*(\n\s*)+/#, with: "\n\n")
                                    .trimmingCharacters(in: .whitespacesAndNewlines))
                                    .font(.body).lineSpacing(4).textSelection(.enabled)
                            }
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(20)
                }
            }
            .navigationTitle("介绍")
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(.hidden, for: .navigationBar)
            .toolbarColorScheme(.light, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button(role: .close) { dismiss() }
                }
            }
        }
        .tint(.primary)
        .presentationBackground { AlbumArtworkBackground(backdrop: backdrop) }
    }
}
