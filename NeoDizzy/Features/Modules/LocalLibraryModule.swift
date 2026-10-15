import SwiftUI

final class LocalLibraryModule: AppModule {
    static var metadata: ModuleDescriptor {
        ModuleDescriptor(id: .localLibrary, title: String(localized: "本地库"), systemImage: "music.note.list")
    }
    var descriptor: ModuleDescriptor { Self.metadata }
    let library: OfflineLibraryStore
    init(library: OfflineLibraryStore) { self.library = library }
    func rootView() -> AnyView { AnyView(LocalLibraryView()) }
    func destination(for route: AppRoute) -> AnyView? {
        guard route.moduleID == descriptor.id, let destination = route.destination.base as? LocalLibraryRoute else { return nil }
        switch destination {
        case .album(let id): return AnyView(LocalAlbumDetailView(id: id))
        case .playlist(let id): return AnyView(LocalPlaylistDetailView(id: id))
        case .albums: return AnyView(LocalAlbumsPage())
        case .playlists: return AnyView(LocalPlaylistsPage())
        case .songs: return AnyView(LocalSongsPage())
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
