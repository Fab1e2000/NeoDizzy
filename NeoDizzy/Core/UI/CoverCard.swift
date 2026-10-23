import SwiftUI

/// Shared artwork card; providers supply presentation values without exposing their models.
struct CoverCard: View {
    let title: String
    let artworkURL: URL?
    var caption: String? = nil
    var reservesTitleLines = false

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            ArtworkImage(url: artworkURL, cornerRadius: 10)
            Text(title)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(DizzyPalette.text)
                .lineLimit(2, reservesSpace: reservesTitleLines)
                .multilineTextAlignment(.leading)
            if let caption {
                Text(caption)
                    .font(.caption)
                    .foregroundStyle(DizzyPalette.mutedText)
            }
        }
        .contentShape(.rect)
        .accessibilityElement(children: .combine)
        .prefetchAlbumArtwork(url: artworkURL)
    }
}
