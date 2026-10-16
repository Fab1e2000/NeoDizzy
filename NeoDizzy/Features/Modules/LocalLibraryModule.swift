import SwiftUI

final class LocalLibraryModule: AppModule {
    static var metadata: ModuleDescriptor {
        ModuleDescriptor(id: .localLibrary, title: String(localized: "资料库"), systemImage: "music.note.list")
    }
    var descriptor: ModuleDescriptor { Self.metadata }
    let library: OfflineLibraryStore
    init(library: OfflineLibraryStore) { self.library = library }
    func rootView() -> AnyView { AnyView(LocalLibraryView()) }
    func searchSection(query: String) -> AnyView? { AnyView(LibrarySearchSection(query: query)) }
    func destination(for route: AppRoute) -> AnyView? {
        guard route.moduleID == descriptor.id, let destination = route.destination.base as? LocalLibraryRoute else { return nil }
        switch destination {
        case .favorites: return AnyView(FavoritesPage())
        case .album(let id): return AnyView(LocalAlbumDetailView(id: id))
        case .playlist(let id): return AnyView(LocalPlaylistDetailView(id: id))
        case .albums(let filter): return AnyView(LocalAlbumsPage(filter: filter))
        case .playlists(let filter): return AnyView(LocalPlaylistsPage(filter: filter))
        case .songs(let filter): return AnyView(LibrarySongsPage(filter: filter))
        case .artists(let filter): return AnyView(LibraryArtistsPage(filter: filter))
        case .artist(let name, let filter): return AnyView(LibrarySongsPage(filter: filter, artist: name))
        case .search(let query): return AnyView(LibrarySearchPage(query: query))
        }
    }
    func handleURL(_ url: URL, host: ModuleHost) -> Bool {
        guard url.isFileURL else { return false }
        host.dismissPresentations = true
        host.select(descriptor.id)
        Task { await library.importItems([url]) }
        return true
    }
}
