import SwiftUI

struct AppRouteDestination: View {
    let route: AppRoute
    var body: some View {
        switch route {
        case .localAlbum(let id): LocalAlbumDetailView(id: id)
        case .disc(let id): DiscDetailView(id: id)
        case .label(let name): LabelDetailView(name: name)
        case .tag(let tag): TagDiscsView(tag: tag)
        case .pack(let id): PackDetailView(id: id)
        case .user(let id): CommunityProfileView(userID: id)
        case .review(let id): ReviewDetailView(id: id)
        }
    }
}
