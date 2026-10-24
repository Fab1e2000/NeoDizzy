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
    static let height = referenceHeight

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

            VStack(alignment: .leading, spacing: 2) {
                Text(song.title)
                    .font(
                        usesReferenceLayout
                            ? .title3.weight(.semibold)
                            : .headline
                    )
                    .lineLimit(1)

                NowPlayingArtistButton(track: song)
                    .font(usesReferenceLayout ? .title3 : .subheadline)
                    .foregroundStyle(.white.opacity(0.64))
                    .lineLimit(1)
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
