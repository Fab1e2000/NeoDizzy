#if os(iOS)
import SwiftUI

/// A visible artwork occurrence, not the collection's business identity.
struct AlbumNavigationSource {
    let id: UUID
    let namespace: Namespace.ID
    let artworkURL: URL
}

extension EnvironmentValues {
    @Entry var albumNavigationNamespace: Namespace.ID? = nil
    /// Scoped to a card's label so only its artwork becomes the zoom source.
    @Entry var albumNavigationSource: AlbumNavigationSource? = nil
}

struct AlbumArtworkTransitionSource: ViewModifier {
    let url: URL?
    let cornerRadius: CGFloat
    @Environment(\.albumNavigationSource) private var source

    @ViewBuilder
    func body(content: Content) -> some View {
        if let source, source.artworkURL == url {
            content.matchedTransitionSource(id: source.id, in: source.namespace) { configuration in
                configuration.clipShape(.rect(cornerRadius: cornerRadius))
            }
        } else {
            content
        }
    }
}

struct AlbumNavigationDestination: ViewModifier {
    let sourceID: UUID?
    let namespace: Namespace.ID

    @ViewBuilder
    func body(content: Content) -> some View {
        if let sourceID {
            content.navigationTransition(.zoom(sourceID: sourceID, in: namespace))
        } else {
            content
        }
    }
}
#endif
