// Direct source port from MeloX (GPL-3.0), b8bc60f.
// Data/settings adapters retain NeoDizzy playback and lyric sources.
import SwiftUI

struct NowPlayingLandscapeView: View {
    @Environment(\.accessibilityReduceMotion) private var accessibilityReduceMotion
    @Environment(PlayerStore.self) private var player

    @Binding var page: NowPlayingPage
    let pageTransition: NowPlayingTransitionCoordinator
    let showsLyricsControls: Bool

    let song: Track
    let lyrics: LocalLyrics?
    let lyricError: String?
    let playerFrame: CGRect
    let artworkNamespace: Namespace.ID
    let onDismiss: () -> Void
    let onInterfaceInteraction: () -> Void
    let onInterfaceVisibilityChange: (Bool) -> Void
    let onLyricsContentPrepared: () -> Void

    var body: some View { standardPlayer }

    private var standardPlayer: some View {
        VStack(spacing: 0) {
            dismissalHandle

            GeometryReader { proxy in
                let artworkSide = min(
                    proxy.size.height,
                    proxy.size.width * 0.43,
                    460
                )

                HStack(spacing: landscapeSpacing(for: proxy.size.width)) {
                    artwork(side: artworkSide)

                    rightPanel
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
                .frame(maxWidth: 1_100, maxHeight: .infinity)
                .frame(maxWidth: .infinity)
            }
        }
        .padding(.horizontal, 20)
        .safeAreaPadding(.top, 2)
        .safeAreaPadding(.bottom, 8)
    }

    private var dismissalHandle: some View {
        Button(action: onDismiss) {
            Capsule()
                .fill(.white.opacity(0.52))
                .frame(width: 38, height: 5)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .frame(height: 28)
        .accessibilityLabel("收起播放器")
        .accessibilityHint("返回上一页")
    }

    private func artwork(side: CGFloat) -> some View {
        ArtworkImage(url: song.coverURL, cornerRadius: 12)
            .frame(width: side, height: side)
            .scaleEffect(player.isPlaying ? 1 : 0.9)
            .shadow(
                color: .black.opacity(
                    player.isPlaying ? 0.32 : 0.18
                ),
                radius: player.isPlaying ? 24 : 14,
                y: player.isPlaying ? 12 : 7
            )
            .animation(.smooth(duration: 0.45), value: player.isPlaying)
            .accessibilityElement()
            .accessibilityLabel("\(song.title)的封面")
    }

    private var rightPanel: some View {
        VStack(spacing: 0) {
            songHeader

            pageContent
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .padding(
                    .bottom,
                    usesExpandedAppleMusicLyricsLayout ? 0 : 50
                )
                .overlay(alignment: .bottom) {
                    pageSelector
                }
        }
    }

    private var pageSelector: some View {
        ZStack {
            NowPlayingPageSelector(page: $page)
                .opacity(hidesLyricsControls ? 0 : 1)
                .allowsHitTesting(!hidesLyricsControls)
                .accessibilityHidden(hidesLyricsControls)


        }
        .frame(height: 50)
    }

    private var hidesLyricsControls: Bool {
        page == .lyrics && !showsLyricsControls
    }

    private var usesExpandedAppleMusicLyricsLayout: Bool {
        page == .lyrics
    }

    private var songHeader: some View { NowPlayingLandscapeSongHeader(song: song) }

    private var pageContent: some View {
        ZStack {
            NowPlayingQueuePage(
                song: song,
                presentation: .landscape,
                artworkNamespace: artworkNamespace
            )
            .nowPlayingQueuePagePresentation(
                visualState:
                    NowPlayingPageTransition.motion
                        .residentQueueState(
                            selectedPage: page,
                            transition: pageTransition.transition
                        ),
                opacityTransition:
                    pageTransition.queueOpacityTransition,
                spatialTransition:
                    pageTransition.queueSpatialTransition,
                opacitySpec:
                    pageTransition.queueOpacityTransition
                        .targetProgress >= 1
                        ? NowPlayingPageTransition.motion
                            .queueOpacityPresentation
                        : NowPlayingPageTransition.motion
                            .queueOpacityDismissal,
                presentationScale:
                    NowPlayingPageTransition.motion
                        .queuePresentationScale,
                reducesMotion: accessibilityReduceMotion
            )
            .allowsHitTesting(page == .queue)
            .accessibilityHidden(page != .queue)

            if page == .artwork {
                landscapeArtworkControls
                    .transition(.opacity)
            }

            residentAppleMusicLyricsPage
        }
    }

    private var residentAppleMusicLyricsPage: some View {
        let motion = NowPlayingPageTransition.motion
        let visualState = motion.residentLyricsState(
            selectedPage: page,
            transition: pageTransition.transition,
            isEntrancePresented:
                pageTransition.isLyricsEntrancePresented
        )

        return NowPlayingLyricsPage(
            song: song,
            lyrics: lyrics,
            errorMessage: lyricError,
            isActive: page == .lyrics,
            presentation: .landscape,
            isInterfaceHidden: hidesLyricsControls,
            artworkNamespace: artworkNamespace,
            playerFrame: playerFrame,
            onInterfaceInteraction: onInterfaceInteraction,
            onInterfaceVisibilityChange:
                onInterfaceVisibilityChange,
            onInitialFocusPrepared: onLyricsContentPrepared
        )
        .id(song.id)
        .nowPlayingLyricsPagePresentation(
            visualState: visualState,
            opacityTransition:
                pageTransition.lyricsOpacityTransition,
            spatialTransition:
                pageTransition.lyricsSpatialTransition,
            opacitySpec:
                pageTransition.lyricsOpacityTransition
                    .targetProgress >= 1
                    ? motion.lyricsOpacityPresentation
                    : motion.lyricsOpacityDismissal,
            presentationScale: motion.lyricsPresentationScale,
            reducesMotion: accessibilityReduceMotion
        )
        .allowsHitTesting(page == .lyrics)
        .accessibilityHidden(page != .lyrics)
        .accessibilityAction(
            named: lyricsInterfaceAccessibilityActionName
        ) {
            onInterfaceInteraction()
        }
    }

    private var landscapeArtworkControls: some View {
        VStack(spacing: 0) {
            Spacer(minLength: 0)
            NowPlayingProgressControl(song: song)
            NowPlayingTransportControls()
            NowPlayingVolumeControl()
            Spacer(minLength: 0)
        }
    }

    private func landscapeSpacing(for width: CGFloat) -> CGFloat {
        min(max(width * 0.035, 18), 38)
    }

    private var lyricsInterfaceAccessibilityActionName: String { "显示播放控件" }

}
