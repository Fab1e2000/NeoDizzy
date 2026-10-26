import LNPopupUI
import Nuke
import SwiftUI
import UIKit

/// 系统负责底部附件的布局；全屏内容由独立呈现容器承载。
struct PlayerPopup: ViewModifier {
    @Binding var isPresented: Bool
    let isSuppressed: Bool
    let colorScheme: ColorScheme
    let onClose: () -> Void

    @Environment(PlayerStore.self) private var player
    @AppStorage(ImmersiveMode.storageKey) private var isImmersive = false
    @State private var transitionState = PlayerTransitionState()
    @State private var artworks: [URL: UIImage] = [:]
    @State private var failedArtworks: Set<URL> = []

    private var shouldShowBar: Bool { player.currentTrack != nil && !isSuppressed }

    func body(content: Content) -> some View {
        content
            // 展开时保留附件及其占位，避免底层滚动页面重新布局。
            .tabViewBottomAccessory(isEnabled: shouldShowBar) {
                if let track = player.currentTrack {
                    SystemMiniPlayer(track: track, artwork: barImage(for:),
                                     transitionState: transitionState, colorScheme: colorScheme) {
                        isPresented = true
                    }
                }
            }
            .background {
                NativePlayerPresentation(isPresented: $isPresented, state: transitionState, onClose: onClose) {
                    NowPlayingView(onDismiss: { isPresented = false })
                        .statusBarHidden(isImmersive)
                        .accessibilityIdentifier("player.fullscreen")
                }
            }
            .onChange(of: shouldShowBar, initial: true) { _, visible in
                if !visible { isPresented = false }
            }
            .task(id: barArtworkURLs) {
                let urls = barArtworkURLs
                artworks = artworks.filter { urls.contains($0.key) }
                failedArtworks.formIntersection(urls)
                updateTransitionArtwork()
                for url in urls where artworks[url] == nil {
                    var request = ImageRequest(url: url)
                    // 转场使用同一张图；足够覆盖全屏封面，避免放大迷你缩略图。
                    request.thumbnail = .init(size: CGSize(width: 900, height: 900), unit: .pixels,
                                              contentMode: .aspectFill)
                    let image = try? await ImagePipeline.shared.image(for: request)
                    guard !Task.isCancelled else { return }
                    if let image {
                        artworks[url] = image
                        failedArtworks.remove(url)
                    } else {
                        failedArtworks.insert(url)
                    }
                    updateTransitionArtwork()
                }
            }
            .onChange(of: player.currentTrack?.id) { updateTransitionArtwork() }
    }

    private var barArtworkURLs: [URL] {
        var seen = Set<URL>()
        return [player.currentTrack, player.previousInOrder?.track, player.nextInOrder?.track]
            .compactMap { $0?.coverURL }.filter { seen.insert($0).inserted }
    }

    private func barImage(for track: Track) -> UIImage {
        if let url = track.coverURL, let image = artworks[url] { return image }
        let showsSymbol = track.coverURL.map { failedArtworks.contains($0) } ?? true
        return MiniPlayerArtworkPlaceholder.image(showsSymbol: showsSymbol, colorScheme: colorScheme)
    }

    private func updateTransitionArtwork() {
        transitionState.artwork = player.currentTrack.map { barImage(for: $0) }
    }
}

private struct SystemMiniPlayer: View {
    let track: Track
    let artwork: (Track) -> UIImage
    let transitionState: PlayerTransitionState
    let colorScheme: ColorScheme
    let open: () -> Void
    @Environment(PlayerStore.self) private var player
    @Environment(\.tabViewBottomAccessoryPlacement) private var placement
    @State private var measuredWidth: CGFloat = 0

    private var compact: Bool {
        placement == .inline || MiniPlayerLayout.usesCompactControls(width: measuredWidth)
    }

    var body: some View {
        PlayerMiniatureContentHost(state: transitionState, height: compact ? 44 : 52) {
            barContent
        }
        .frame(height: compact ? 44 : 52)
        .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { measuredWidth = $0 }
        .accessibilityIdentifier("mini.player")
    }

    private var barContent: some View {
        HStack(spacing: 0) {
            NowPlayingTrackSwipe(song: track) { song, interactive in
                Button(action: open) {
                    HStack(spacing: 10) {
                        PlayerMiniatureArtwork(image: artwork(song), state: transitionState, isCurrent: interactive)
                            .frame(width: compact ? 32 : 40, height: compact ? 32 : 40)
                        VStack(alignment: .leading, spacing: 2) {
                            NowPlayingMarqueeText(text: song.title, isActive: interactive)
                                .font(.system(size: 15, weight: .medium))
                            if !compact {
                                Text(song.artists)
                                    .font(.system(size: 12))
                                    .foregroundStyle(.secondary)
                                    .lineLimit(1)
                            }
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .contentShape(.rect)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("展开播放器，" + song.title)
                .accessibilityIdentifier("mini.open")
            }
            .clipped()
            .gesture(MiniPlayerOpenPan(open: open))
            MiniPlayerControls(isPlaying: player.isPlaying, isLoading: player.isLoading,
                               canPlayNext: player.canPlayNext, compact: compact,
                               colorScheme: colorScheme,
                               togglePlayback: player.togglePlayback, next: player.next)
        }
        .padding(.leading, compact ? 8 : 10)
        .padding(.trailing, 2)
        .frame(height: compact ? 44 : 52)
        .foregroundStyle(colorScheme == .dark ? Color.white : Color.black)
        .environment(\.colorScheme, colorScheme)
    }
}

/// A real rendered hosting view gives LN a live miniature portal. No transparent
/// geometry marker or duplicated screenshot is substituted for the source.
private struct PlayerMiniatureContentHost<Content: View>: UIViewControllerRepresentable {
    let state: PlayerTransitionState
    let height: CGFloat
    let content: () -> Content

    init(state: PlayerTransitionState, height: CGFloat, @ViewBuilder content: @escaping () -> Content) {
        self.state = state
        self.height = height
        self.content = content
    }

    func makeUIViewController(context: Context) -> UIHostingController<AnyView> {
        let controller = UIHostingController(rootView: AnyView(content().environment(\.self, context.environment)))
        controller.safeAreaRegions = []
        controller.view.backgroundColor = .clear
        controller.view.accessibilityIdentifier = "mini.player.content"
        state.externalSource.contentView = controller.view
        state.externalSource.cornerRadius = height / 2
        return controller
    }

    func updateUIViewController(_ controller: UIHostingController<AnyView>, context: Context) {
        controller.rootView = AnyView(content().environment(\.self, context.environment))
        state.externalSource.contentView = controller.view
        state.externalSource.cornerRadius = height / 2
    }

    func sizeThatFits(_ proposal: ProposedViewSize, uiViewController: UIHostingController<AnyView>,
                     context: Context) -> CGSize? {
        CGSize(width: proposal.width ?? 320, height: height)
    }
}

/// LN's source artwork is the actual image view, allowing its original portal,
/// corner interpolation and source-layer hiding to work without a separate flight.
private struct PlayerMiniatureArtwork: UIViewRepresentable {
    let image: UIImage
    let state: PlayerTransitionState
    let isCurrent: Bool

    func makeUIView(context: Context) -> UIImageView {
        let view = UIImageView()
        view.contentMode = .scaleAspectFill
        view.clipsToBounds = true
        view.layer.cornerCurve = .continuous
        view.layer.cornerRadius = 6
        view.setContentHuggingPriority(.defaultLow, for: .horizontal)
        view.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        view.setContentHuggingPriority(.defaultLow, for: .vertical)
        view.setContentCompressionResistancePriority(.defaultLow, for: .vertical)
        updateUIView(view, context: context)
        return view
    }

    func sizeThatFits(_ proposal: ProposedViewSize, uiView: UIImageView, context: Context) -> CGSize? {
        guard let width = proposal.width, let height = proposal.height else { return nil }
        // LN converts this UIView's actual bounds into its transition endpoint.
        // A clipped 40pt SwiftUI slot must not contain a 900pt-tall UIImageView.
        return CGSize(width: width, height: height)
    }

    func updateUIView(_ view: UIImageView, context: Context) {
        view.image = image
        if isCurrent {
            state.externalSource.artworkView = view
            state.externalSource.artworkCornerRadius = 6
        } else if state.externalSource.artworkView === view {
            state.externalSource.artworkView = nil
        }
    }
}

/// 和 LN 的默认闭合态一样，向上滑动触发展开；横向手势仍交给相邻曲目。
private struct MiniPlayerOpenPan: UIGestureRecognizerRepresentable {
    let open: () -> Void
    func makeCoordinator(converter: CoordinateSpaceConverter) -> Coordinator { Coordinator() }
    func makeUIGestureRecognizer(context: Context) -> UIPanGestureRecognizer {
        let pan = UIPanGestureRecognizer()
        pan.delegate = context.coordinator
        return pan
    }
    func handleUIGestureRecognizerAction(_ pan: UIPanGestureRecognizer, context: Context) {
        guard pan.state == .began else { return }
        // LN's automatic closed state resolves to snap: recognize upward intent,
        // then open after its original 150 ms handoff, without waiting for release.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) { open() }
    }
    final class Coordinator: NSObject, UIGestureRecognizerDelegate {
        func gestureRecognizerShouldBegin(_ recognizer: UIGestureRecognizer) -> Bool {
            guard let pan = recognizer as? UIPanGestureRecognizer else { return false }
            let velocity = pan.velocity(in: pan.view)
            return velocity.y < 0 && abs(velocity.y) > abs(velocity.x)
        }
    }
}

@MainActor private enum MiniPlayerArtworkPlaceholder {
    private static var cache: [String: UIImage] = [:]
    static func image(showsSymbol: Bool, colorScheme: ColorScheme) -> UIImage {
        let key = "\(showsSymbol)-\(colorScheme)"
        if let image = cache[key] { return image }
        let renderer = ImageRenderer(content: ZStack {
            DizzyPalette.artworkPlaceholder
            if showsSymbol {
                Image(systemName: "music.note")
                    .font(.system(size: 64))
                    .foregroundStyle(DizzyPalette.artworkPlaceholderSymbol)
            }
        }
        .frame(width: 160, height: 160)
        .environment(\.colorScheme, colorScheme))
        renderer.scale = 1
        let image = renderer.uiImage ?? UIImage()
        cache[key] = image
        return image
    }
}

/// 固定宽度的播放控制，加载和播放状态切换时不挤动标题。
struct MiniPlayerControls: View {
    @Environment(\.accessibilityReduceMotion) private var reducesMotion
    /// 每点一次下一首加一，触发图标的推进动画。
    @State private var nextTrigger = 0
    @State private var showsLoadingIndicator = false

    let isPlaying: Bool
    let isLoading: Bool
    let canPlayNext: Bool
    let compact: Bool
    let colorScheme: ColorScheme
    let togglePlayback: () -> Void
    let next: () -> Void

    var body: some View {
        HStack(spacing: 0) {
            Button(action: togglePlayback) {
                // 尺寸接近 17pt semibold 的 play.fill / pause.fill。
                NowPlayingPlayPauseIcon(isPlaying: isPlaying, reducesMotion: reducesMotion, cornerRadius: 2)
                    .frame(width: 13, height: 15)
                    .opacity(showsLoadingIndicator ? 0 : 1)
                    .frame(width: 44, height: 44)
                    .overlay {
                        if showsLoadingIndicator {
                            ProgressView()
                                .allowsHitTesting(false)
                                .transition(.opacity)
                        }
                    }
                    .contentShape(.rect)
            }
            // 和播放页一样：加载持续 0.3 秒以上才换成转圈，切歌、暂停时不闪。
            .task(id: isLoading) {
                if isLoading {
                    try? await Task.sleep(for: .milliseconds(300))
                    guard !Task.isCancelled else { return }
                }
                withAnimation(reducesMotion ? nil : .smooth(duration: 0.2)) {
                    showsLoadingIndicator = isLoading
                }
            }
            .buttonStyle(MiniPlayerPressStyle(reducesMotion: reducesMotion))
            .accessibilityLabel(isPlaying ? "暂停" : "播放")
            .accessibilityIdentifier("mini.playPause")
            if !compact {
                Button {
                    nextTrigger += 1
                    next()
                } label: {
                    // 尺寸接近 17pt semibold 的 forward.fill。
                    NowPlayingSkipIcon(direction: .forward, trigger: nextTrigger,
                                       reducesMotion: reducesMotion, cornerRadius: 1.2)
                        .frame(width: 24, height: 13.5)
                        .frame(width: 44, height: 44)
                        .contentShape(.rect)
                }
                .disabled(!canPlayNext)
                .accessibilityLabel("下一首")
                .accessibilityIdentifier("mini.next")
            }
        }
        .font(.system(size: 17, weight: .semibold))
        .buttonStyle(.plain)
        .tint(colorScheme == .dark ? Color.white : .black)
        .foregroundStyle(colorScheme == .dark ? Color.white : .black)
        .environment(\.colorScheme, colorScheme)
        .fixedSize()
    }
}

nonisolated enum MiniPlayerLayout {
    static func usesCompactControls(width: CGFloat) -> Bool { width > 0 && width < 300 }
}

/// 迷你播放器的播放/暂停按钮：按下压缩，松手带过冲弹回。
private struct MiniPlayerPressStyle: ButtonStyle {
    let reducesMotion: Bool

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed && !reducesMotion ? 0.8 : 1)
            .animation(
                reducesMotion
                    ? nil
                    : configuration.isPressed
                        ? .easeOut(duration: 0.12)
                        : .spring(duration: 0.45, bounce: 0.5),
                value: configuration.isPressed
            )
    }
}
