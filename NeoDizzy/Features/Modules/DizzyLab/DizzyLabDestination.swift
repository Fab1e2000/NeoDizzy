import SwiftUI

struct DizzyLabDestination: View {
    @Environment(PlayerStore.self) private var player
    @Environment(NowPlayingPresentation.self) private var nowPlaying
    @Environment(DizzyLabContentCache.self) private var contentCache
    let route: DizzyLabRoute
    var body: some View {
        switch route {
        case .section(let section):
            switch section {
            case .shuffle:
                ShuffleView { selection in
                    player.playDiscovery(selection)
                    nowPlaying.isPresented = true
                }
            case .labels: LabelsView()
            case .feed: FeedView()
            case .purchased: PurchasedLibraryView()
            }
        case .disc(let id): DiscDetailView(id: id, cachedModel: contentCache.disc(id), initialArtworkURL: contentCache.artwork(for: id))
        case .label(let name): LabelDetailView(name: name)
        case .tag(let tag): TagDiscsView(tag: tag)
        case .pack(let id): PackDetailView(id: id)
        case .search(let query): DizzyLabSearchPage(query: query)
        case .user(let id): CommunityProfileView(userID: id)
        case .review(let id): ReviewDetailView(id: id)
        case .discCommunity(let id): DiscCommunityPage(discID: id)
        }
    }
}
