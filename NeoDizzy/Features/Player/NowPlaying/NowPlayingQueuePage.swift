// Direct source port from MeloX (GPL-3.0), b8bc60f.
// NeoDizzy adapters are limited to track data, available playback features and localization.
import SwiftUI

struct NowPlayingQueuePage: View {
    @Environment(PlayerStore.self) private var player
    @Environment(\.nowPlayingLayout) private var layout

    let song: Track
    let presentation: NowPlayingLyricsPresentation
    let artworkNamespace: Namespace.ID
    let usesArtworkTransition: Bool
    let showsSongHeader: Bool
    let onSongHeaderHiddenChange: (Bool) -> Void
    let onSongHeaderOffsetChange: (CGFloat) -> Void

    private static let contentHorizontalInset: CGFloat = 32

    @State private var scrollOffset: CGFloat = 0
    @State private var isSongHeaderHidden = false
    @State private var isSongHeaderAtRest = true

    init(
        song: Track,
        presentation: NowPlayingLyricsPresentation,
        artworkNamespace: Namespace.ID,
        usesArtworkTransition: Bool = true,
        showsSongHeader: Bool = true,
        onSongHeaderHiddenChange:
            @escaping (Bool) -> Void = { _ in },
        onSongHeaderOffsetChange:
            @escaping (CGFloat) -> Void = { _ in }
    ) {
        self.song = song
        self.presentation = presentation
        self.artworkNamespace = artworkNamespace
        self.usesArtworkTransition = usesArtworkTransition
        self.showsSongHeader = showsSongHeader
        self.onSongHeaderHiddenChange = onSongHeaderHiddenChange
        self.onSongHeaderOffsetChange = onSongHeaderOffsetChange
    }

    var body: some View {
        VStack(spacing: 0) {
            NowPlayingQueueList(
                entries: upcomingEntries,
                headerHeight: songHeaderHeight,
                horizontalInset: Self.contentHorizontalInset,
                onPlay: { player.playFromQueue(at: $0) },
                onMove: moveQueueItems,
                onScroll: updateSongHeaderState
            )
            // 列表外面有渐隐遮罩，行里作者名的叠加提亮要和遮罩里的背景副本叠加。
            .nowPlayingBackdropUnderlay(artworkURL: player.currentTrack?.coverURL)
            // 页面外层有 32pt 的水平内边距；列表自己向两侧多出同样的宽度，行内容再缩进回来。
            .mask {
                // Fade the last row into the live player backdrop without
                // introducing a tinted material strip above the scrubber.
                VStack(spacing: 0) {
                    NowPlayingQueueTopFade(height: 24)
                    Rectangle()
                    LinearGradient(
                        stops: [
                            .init(color: .black, location: 0),
                            .init(color: .black.opacity(0.8), location: 0.35),
                            .init(color: .black.opacity(0.35), location: 0.7),
                            .init(color: .clear, location: 1)
                        ],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                    .frame(height: 80)
                }
                    .padding(.horizontal, -Self.contentHorizontalInset)
                    .padding(.top, modeControlsOffset + 60)
            }
            .overlay(alignment: .top) {
                NowPlayingQueueModeControls()
                    .padding(.vertical, 8)
                    .frame(height: 60)
                    .offset(y: modeControlsOffset)
            }
            .overlay(alignment: .top) {
                if presentation == .portrait && showsSongHeader {
                    NowPlayingSongHeader(
                        song: song,
                        artworkNamespace: artworkNamespace,
                        usesReferenceLayout: true,
                        usesArtworkTransition: usesArtworkTransition && isSongHeaderAtRest
                    )
                    .frame(height: NowPlayingSongHeader.referenceHeight)
                    .padding(.top, NowPlayingSongHeader.topInset)
                    .frame(height: songHeaderHeight, alignment: .top)
                    .offset(y: -scrollOffset)
                    .opacity(NowPlayingSongHeader.scrollFadeOpacity(scrolled: scrollOffset))
                }
            }
            .padding(.bottom, bottomContentInset)
        }
        .onAppear {
            if presentation == .portrait {
                scrollOffset = 0
                isSongHeaderHidden = false
                isSongHeaderAtRest = true
                onSongHeaderHiddenChange(false)
                onSongHeaderOffsetChange(0)
            }
        }
    }

    private var upcomingEntries: [UpcomingQueueEntry] {
        var occurrences: [String: Int] = [:]
        return player.upcoming.map { entry in
            let occurrence = occurrences[entry.track.id, default: 0]
            occurrences[entry.track.id] = occurrence + 1
            return UpcomingQueueEntry(
                id: .init(songID: entry.track.id, occurrence: occurrence),
                queueIndex: entry.index, song: entry.track
            )
        }
    }

    /// 头部占的整段高度：上方留白、头部本身、到模式按钮的间距。
    private var songHeaderHeight: CGFloat {
        presentation == .portrait
            ? NowPlayingSongHeader.topInset + NowPlayingSongHeader.referenceHeight
                + NowPlayingSongHeader.bottomSpacing
            : 0
    }

    private var modeControlsOffset: CGFloat {
        max(songHeaderHeight - scrollOffset, 0)
    }

    private var bottomContentInset: CGFloat {
        // Leave a small gap above the progress track, halfway between the
        // original fixed inset and the track-aligned version.
        presentation == .portrait
            ? max(0, layout.contentSize.height - 3 - layout.contentY(567.25))
            : 12
    }

    private func updateSongHeaderState(for offset: CGFloat) {
        guard presentation == .portrait else { return }
        scrollOffset = offset

        onSongHeaderOffsetChange(
            -min(offset, max(songHeaderHeight, 0))
        )

        let isHidden =
            songHeaderHeight > 0
            && offset >= songHeaderHeight
        if isSongHeaderHidden != isHidden {
            isSongHeaderHidden = isHidden
            onSongHeaderHiddenChange(isHidden)
        }

        let isAtRest = offset <= 0.5
        if isSongHeaderAtRest != isAtRest {
            isSongHeaderAtRest = isAtRest
        }
    }

    private func moveQueueItems(
        from source: IndexSet,
        to destination: Int
    ) {
        withAnimation(.smooth(duration: 0.28)) {
            player.moveUpcomingQueueItems(
                fromOffsets: source,
                toOffset: destination
            )
        }
    }
}

/// A short transparent-to-opaque edge shared by the queue and its header.
struct NowPlayingQueueTopFade: View {
    let height: CGFloat

    var body: some View {
        LinearGradient(
            stops: [
                .init(color: .clear, location: 0),
                .init(color: .black.opacity(0.35), location: 0.3),
                .init(color: .black.opacity(0.8), location: 0.65),
                .init(color: .black, location: 1)
            ],
            startPoint: .top,
            endPoint: .bottom
        )
        .frame(height: height)
    }
}

private struct NowPlayingQueueModeControls: View {
    @Environment(PlayerStore.self) private var player

    var body: some View {
        HStack(spacing: 14) {
            modeButton(
                systemImage: "shuffle",
                isSelected: player.isShuffled,
                accessibilityLabel:
                    player.isShuffled
                        ? "关闭随机播放"
                        : "随机播放",
                action: toggleShuffle
            )

            modeButton(
                systemImage: player.repeatMode.systemImage,
                isSelected: player.repeatMode != .off,
                accessibilityLabel:
                    player.repeatMode.accessibilityTitle,
                action: cycleRepeatMode
            )

        }
        .disabled(player.isDiscovery)
    }

    private func modeButton(
        systemImage: String,
        isSelected: Bool,
        accessibilityLabel: String,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .contentTransition(
                    .symbolEffect(.replace.downUp.wholeSymbol)
                )
                .font(.title3.weight(.semibold))
                .frame(maxWidth: .infinity)
                .frame(height: 44)
                .foregroundStyle(
                    isSelected
                        ? .black.opacity(0.62)
                        : .white.opacity(0.86)
                )
                .background(
                    .white.opacity(isSelected ? 0.7 : 0.12),
                    in: .rect(cornerRadius: 22)
                )
                .contentShape(.rect(cornerRadius: 22))
        }
        .buttonStyle(.plain)
        .accessibilityLabel(accessibilityLabel)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }

    private func toggleShuffle() {
        withAnimation(.smooth(duration: 0.34)) {
            player.toggleShuffle()
        }
    }

    private func cycleRepeatMode() {
        withAnimation(.smooth(duration: 0.34)) {
            player.cycleRepeatMode()
        }
    }

}

struct NowPlayingQueueRow: View {
    let entry: UpcomingQueueEntry
    let onPlay: () -> Void

    var body: some View {
        Button(action: onPlay) {
            HStack(spacing: 12) {
                ArtworkImage(
                    url: entry.song.coverURL,
                    cornerRadius: 6
                )
                .frame(width: 48, height: 48)

                VStack(alignment: .leading, spacing: 2) {
                    Text(entry.song.title)
                        .font(.body)
                        .foregroundStyle(.white)
                        .lineLimit(1)

                    // 和头部作者名一样做叠加提亮（见 NowPlayingArtistButton）。
                    Text(entry.song.artists)
                        .font(.subheadline)
                        .foregroundStyle(.white.opacity(0.46))
                        .blendMode(.plusLighter)
                        .lineLimit(1)
                }

                Spacer(minLength: 4)
            }
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
    }
}
