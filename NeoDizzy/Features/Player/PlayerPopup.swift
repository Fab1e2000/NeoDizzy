import LNPopupUI
import Nuke
import SwiftUI
import UIKit

/// Shared presentation adapter; playback and full-screen content retain their existing owners.
struct PlayerPopup: ViewModifier {
    @Binding var isPresented: Bool
    let isSuppressed: Bool
    let colorScheme: ColorScheme
    let onClose: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reducesMotion
    @Environment(PlayerStore.self) private var player
    @AppStorage(ImmersiveMode.storageKey) private var isImmersive = false
    @State private var isBarPresented = false
    @State private var artwork: UIImage?
    @State private var compactControls = false
    @State private var appearance = PlayerPopupAppearance()

    private var shouldShowBar: Bool { player.currentTrack != nil && !isSuppressed }

    func body(content: Content) -> some View {
        content
            .popup(isBarPresented: $isBarPresented, isPopupOpen: $isPresented, onClose: onClose) {
                PlayerPopupContent(barImage: barImage, compact: compactControls, colorScheme: colorScheme) { isPresented = false }
                    .statusBarHidden(isImmersive)
            }
            .popupBarStyle(.floatingCompact)
            // Keep the floating material independent of an opaque docking-bar appearance.
            .popupBarInheritsAppearanceFromDockingView(false)
            .popupBarCustomizer { bar in
                appearance.apply(to: bar, colorScheme: colorScheme)
            }
            .popupContentViewCustomizer { view in
                view.overrideUserInterfaceStyle = .dark
                view.popupInteractionGestureRecognizer.delegate = appearance
            }
            .popupInteractionStyle(.automatic)
            .popupCloseButtonStyle(.none)
            .popupBarMarqueeScrollEnabled(!compactControls)
            .onPopupBarGeometryChange(for: Bool.self, of: { proxy in
                MiniPlayerLayout.usesCompactControls(width: proxy.effectiveBarContentSize.width)
            }) { compactControls = $0 }
            .onChange(of: shouldShowBar, initial: true) { _, visible in
                if !visible { isPresented = false }
                isBarPresented = visible
            }
            .task(id: player.currentTrack?.coverURL) {
                guard let url = player.currentTrack?.coverURL else { return }
                var request = ImageRequest(url: url)
                request.thumbnail = .init(size: CGSize(width: 160, height: 160), unit: .pixels,
                                          contentMode: .aspectFill)
                let image = try? await ImagePipeline.shared.image(for: request)
                guard !Task.isCancelled else { return }
                if let image { artwork = image }
            }
    }

    private var barImage: PopupItemViewImage {
        PopupItemViewImage {
            if let artwork {
                NowPlayingBackdropImage(image: artwork, animated: !reducesMotion)
            } else {
                Color.clear
            }
        }
    }

}

private struct PlayerPopupContent: View {
    let barImage: PopupItemViewImage
    let compact: Bool
    let colorScheme: ColorScheme
    let onDismiss: () -> Void
    @Environment(PlayerStore.self) private var player
    @Environment(\.popupBarPlacement) private var placement

    var body: some View {
        let isCompact = compact || placement == .inline
        Group {
            if let track = player.currentTrack {
                NowPlayingView(onDismiss: onDismiss)
                    .popupItem {
                        PopupItem(id: track.id, image: barImage, title: {
                            MiniPlayerTitlePager(height: isCompact ? 18 : 36, song: track, currentIndex: player.currentQueueIndex,
                                                 previous: player.previousInOrder, next: player.nextInOrder,
                                                 select: player.skip(toQueueIndex:)) { song, interactive in
                                VStack(alignment: .leading, spacing: 2) {
                                    NowPlayingMarqueeText(text: song.title, isActive: interactive && !isCompact)
                                        .font(.system(size: 15, weight: .medium))
                                        .foregroundStyle(colorScheme == .dark ? Color.white : .black)
                                    if !isCompact {
                                        Text(song.artists)
                                            .font(.system(size: 12))
                                            .foregroundStyle(.secondary)
                                    }
                                }
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .contentShape(.rect)
                            }
                            .frame(height: isCompact ? 18 : 36)
                            .clipped()
                            .environment(player)
                            .environment(\.colorScheme, colorScheme)
                            .accessibilityIdentifier("mini.trackTitle")
                        }, buttons: {
                            ToolbarItem(placement: .popupBar) {
                                MiniPlayerControls(isPlaying: player.isPlaying, isLoading: player.isLoading,
                                                   canPlayNext: player.canPlayNext, compact: isCompact,
                                                   colorScheme: colorScheme,
                                                   togglePlayback: player.togglePlayback, next: player.next)
                            }
                        })
                    }
            }
        }
    }
}

/// One fixed-size toolbar item gives LN a single, stable title exclusion rect.
struct MiniPlayerControls: View {
    let isPlaying: Bool
    let isLoading: Bool
    let canPlayNext: Bool
    let compact: Bool
    let colorScheme: ColorScheme
    let togglePlayback: () -> Void
    let next: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reducesMotion
    @State private var nextTrigger = 0
    @State private var showsLoadingIndicator = false

    var body: some View {
        HStack(spacing: 0) {
            Button(action: togglePlayback) {
                ZStack {
                    NowPlayingPlayPauseIcon(isPlaying: isPlaying, reducesMotion: reducesMotion,
                                            cornerRadius: 2.2)
                        .frame(width: 14, height: 18)
                        .opacity(showsLoadingIndicator ? 0 : 1)
                        .scaleEffect(showsLoadingIndicator ? 0.6 : 1)
                    if showsLoadingIndicator {
                        ProgressView().allowsHitTesting(false).transition(.opacity)
                    }
                }
                .frame(width: 44, height: 44)
                .task(id: isLoading) {
                    if isLoading {
                        try? await Task.sleep(for: .milliseconds(300))
                        guard !Task.isCancelled else { return }
                    }
                    withAnimation(reducesMotion ? nil : .smooth(duration: 0.2)) {
                        showsLoadingIndicator = isLoading
                    }
                }
            }
            .buttonStyle(NowPlayingTransportButtonStyle(reducesMotion: reducesMotion,
                                                        springsBack: true, diameter: 44))
            .accessibilityLabel(isPlaying ? "暂停" : "播放")
            .accessibilityIdentifier("mini.playPause")
            if !compact {
                Button {
                    nextTrigger += 1
                    next()
                } label: {
                    NowPlayingSkipIcon(direction: .forward, trigger: nextTrigger,
                                       reducesMotion: reducesMotion, cornerRadius: 1.3)
                        .frame(width: 23, height: 15.5)
                        .frame(width: 44, height: 44)
                }
                .buttonStyle(NowPlayingTransportButtonStyle(reducesMotion: reducesMotion, diameter: 44))
                .disabled(!canPlayNext)
                .accessibilityLabel("下一首")
                .accessibilityIdentifier("mini.next")
            }
        }
        .tint(colorScheme == .dark ? Color.white : .black)
        .foregroundStyle(colorScheme == .dark ? Color.white : .black)
        .environment(\.colorScheme, colorScheme)
        .fixedSize()
    }
}

nonisolated enum MiniPlayerLayout {
    static func usesCompactControls(width: CGFloat) -> Bool { width > 0 && width < 300 }
}

/// Only reconfigure material when the destination appearance actually changes.
/// Recreating it for every popup/content update can introduce a light intermediate frame.
@MainActor final class PlayerPopupAppearance: NSObject, UIGestureRecognizerDelegate {
    func gestureRecognizerShouldBegin(_ gestureRecognizer: UIGestureRecognizer) -> Bool {
        guard let pan = gestureRecognizer as? UIPanGestureRecognizer else { return true }
        let travel = pan.translation(in: pan.view)
        return abs(travel.y) >= abs(travel.x)
    }

    private weak var installedBar: LNPopupBar?
    private var installedStyle: UIUserInterfaceStyle?

    func apply(to bar: LNPopupBar, colorScheme: ColorScheme) {
        let style: UIUserInterfaceStyle = colorScheme == .dark ? .dark : .light
        guard installedBar !== bar || installedStyle != style else { return }
        UIView.performWithoutAnimation {
            bar.overrideUserInterfaceStyle = style
            bar.tintColor = .label
            let appearance = LNPopupBarAppearance()
            appearance.configureWithTransparentBackground()
            appearance.configureWithDefaultFloatingBackground()
            bar.standardAppearance = appearance
            bar.inlineAppearance = appearance
        }
        installedBar = bar
        installedStyle = style
    }
}
