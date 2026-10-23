// Direct source port from MeloX (GPL-3.0), b8bc60f.
// NeoDizzy adapters are limited to track data, available playback features and localization.
import SwiftUI

struct NowPlayingBottomControls: View {
    static let utilityHeight: CGFloat = 62
    static let coreHeight: CGFloat = 279
    static let overlayHeight = utilityHeight + coreHeight

    @Environment(\.accessibilityReduceMotion)
    private var accessibilityReduceMotion

    let song: Track
    @Binding var page: NowPlayingPage
    let hasLyrics: Bool
    let showsLyricsUtilities: Bool
    let hasLyricsTranslations: Bool
    let hasLyricsRomanizations: Bool
    let isInterfaceHidden: Bool

    var body: some View {
        VStack(spacing: 0) {
            // Reserved utility row follows MeloX's overlay geometry. LocalLyrics
            // has no independently selectable translation/romanization channels.
            Color.clear.frame(height: Self.utilityHeight)

            coreControls
        }
        .frame(height: Self.overlayHeight)
    }

    private var coreControls: some View {
        VStack(spacing: 0) {
            interfaceLayer(.progress) {
                NowPlayingProgressControl(song: song)
            }

            Color.clear
                .frame(height: 19)

            interfaceLayer(.transport) {
                NowPlayingTransportControls()
            }

            Color.clear
                .frame(height: 31)

            interfaceLayer(.volume) {
                NowPlayingVolumeControl()
            }

            Color.clear
                .frame(height: 3)

            interfaceLayer(.pageSelector) {
                NowPlayingPageSelector(page: $page, hasLyrics: hasLyrics)
            }
        }
        .frame(height: Self.coreHeight)
        .background {
            Color.clear
                .contentShape(.rect)
                .onTapGesture {}
        }
    }

    private func interfaceLayer<Content: View>(
        _ layer: NowPlayingInterfaceTransition.ControlLayer,
        @ViewBuilder content: () -> Content
    ) -> some View {
        content()
            .offset(
                y: isInterfaceHidden
                    ? NowPlayingInterfaceTransition.hiddenOffset(
                        for: layer
                    )
                    : 0
            )
            .opacity(isInterfaceHidden ? 0 : 1)
            .animation(
                NowPlayingInterfaceTransition.controlAnimation(
                    for: layer,
                    isVisible: !isInterfaceHidden,
                    reducesMotion: accessibilityReduceMotion
                ),
                value: isInterfaceHidden
            )
    }
}

