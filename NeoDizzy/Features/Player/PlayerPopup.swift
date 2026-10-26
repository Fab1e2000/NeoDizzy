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

    @Environment(PlayerStore.self) private var player
    @AppStorage(ImmersiveMode.storageKey) private var isImmersive = false
    @State private var isBarPresented = false
    @State private var artwork: UIImage?
    @State private var loadedArtworkURL: URL?
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
                artwork = nil
                loadedArtworkURL = nil
                guard let url = player.currentTrack?.coverURL else { return }
                var request = ImageRequest(url: url)
                request.thumbnail = .init(size: CGSize(width: 160, height: 160), unit: .pixels,
                                          contentMode: .aspectFill)
                let image = try? await ImagePipeline.shared.image(for: request)
                guard !Task.isCancelled else { return }
                artwork = image
                loadedArtworkURL = url
            }
    }

    private var barImage: Image {
        if loadedArtworkURL == player.currentTrack?.coverURL, let artwork {
            return Image(uiImage: artwork)
        }
        return Image(systemName: "music.note")
    }
}

private struct PlayerPopupContent: View {
    let barImage: Image
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
                            NowPlayingTrackSwipe(song: track, usesUIKitTouchSurface: true) { song, interactive in
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

    var body: some View {
        HStack(spacing: 0) {
            Button(action: togglePlayback) {
                Image(systemName: isPlaying ? "pause.fill" : "play.fill")
                    .opacity(isLoading ? 0 : 1)
                    .frame(width: 44, height: 44)
                    .overlay { if isLoading { ProgressView().allowsHitTesting(false) } }
                    .contentShape(.rect)
            }
            .accessibilityLabel(isPlaying ? "暂停" : "播放")
            .accessibilityIdentifier("mini.playPause")
            if !compact {
                Button(action: next) {
                    Image(systemName: "forward.fill").frame(width: 44, height: 44).contentShape(.rect)
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
