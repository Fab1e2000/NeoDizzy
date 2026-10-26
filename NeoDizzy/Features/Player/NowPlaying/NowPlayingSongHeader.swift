// Direct source port from MeloX (GPL-3.0), b8bc60f.
// NeoDizzy adapters are limited to track data, available playback features and localization.
import SwiftUI

struct NowPlayingArtworkTransitionModifier<ID: Hashable>: ViewModifier {
    let id: ID
    let namespace: Namespace.ID
    let isEnabled: Bool
    let isSource: Bool

    @ViewBuilder
    func body(content: Content) -> some View {
        if isEnabled {
            content.matchedGeometryEffect(
                id: id,
                in: namespace,
                properties: .frame,
                isSource: isSource
            )
        } else {
            content
        }
    }
}

extension View {
    func nowPlayingArtworkTransition<ID: Hashable>(
        id: ID,
        in namespace: Namespace.ID,
        isEnabled: Bool,
        isSource: Bool = true
    ) -> some View {
        modifier(
            NowPlayingArtworkTransitionModifier(
                id: id,
                namespace: namespace,
                isEnabled: isEnabled,
                isSource: isSource
            )
        )
    }
}

struct NowPlayingSongHeader: View {
    static let referenceHeight: CGFloat = 72
    /// 竖屏共用头部离页面顶部（收起把手下方）的留白，参照系统音乐。
    static let topInset: CGFloat = 17
    /// 「继续播放」页里头部下沿到模式按钮之间多留的距离。
    static let bottomSpacing: CGFloat = 8
    static let height = referenceHeight

    /// 头部往上滚时的透明度：一开始滚就变淡，滚 30pt 淡完，几乎不会盖到顶部的收起把手。
    /// 只用透明度，不用渐隐遮罩或裁剪：这两种都会让头部单独合成，作者名的叠加提亮就失效了。
    static func scrollFadeOpacity(scrolled: CGFloat) -> Double {
        1 - min(1, max(0, scrolled / 30))
    }

    let song: Track
    let artworkNamespace: Namespace.ID
    let usesReferenceLayout: Bool
    let usesArtworkTransition: Bool
    let showsArtwork: Bool
    var onImportLyrics: (() -> Void)? = nil

    init(
        song: Track,
        artworkNamespace: Namespace.ID,
        usesReferenceLayout: Bool,
        usesArtworkTransition: Bool = true,
        showsArtwork: Bool = true,
        onImportLyrics: (() -> Void)? = nil
    ) {
        self.onImportLyrics = onImportLyrics
        self.song = song
        self.artworkNamespace = artworkNamespace
        self.usesReferenceLayout = usesReferenceLayout
        self.usesArtworkTransition = usesArtworkTransition
        self.showsArtwork = showsArtwork
    }

    var body: some View {
        HStack(spacing: 12) {
            artwork
                .frame(width: artworkSize, height: artworkSize)

            // 左右滑动歌名切到上一首/下一首。
            NowPlayingTrackSwipe(song: song) { track, interactive in
                VStack(alignment: .leading, spacing: 2) {
                    // 放不下时滚动显示（相邻曲目的预览不滚）。
                    NowPlayingMarqueeText(text: track.title, isActive: interactive)
                        .font(
                            usesReferenceLayout
                                ? .title3.weight(.semibold)
                                : .headline
                        )
                        .lineLimit(1)

                    NowPlayingArtistButton(track: track, interactive: interactive)
                        .font(usesReferenceLayout ? .title3 : .subheadline)
                        .lineLimit(1)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(.rect)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            NowPlayingSongActions(
                track: song, onImportLyrics: onImportLyrics
            )
        }
    }

    @ViewBuilder
    private var artwork: some View {
        if showsArtwork {
            ArtworkImage(
                url: song.coverURL,
                cornerRadius: usesReferenceLayout ? 12 : 10
            )
            .nowPlayingArtworkTransition(
                id: song.id,
                in: artworkNamespace,
                isEnabled: usesArtworkTransition,
                isSource: false
            )
        } else {
            Color.clear
        }
    }

    private var artworkSize: CGFloat {
        usesReferenceLayout ? Self.referenceHeight : 68
    }

    private var artistText: String {
        guard usesReferenceLayout else { return song.artists }
        return song.artists
    }
}
