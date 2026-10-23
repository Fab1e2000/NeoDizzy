import SwiftUI

final class NeteaseModule: AppModule {
    static var metadata: ModuleDescriptor { .init(id: .netease, title: "网易云音乐", systemImage: "music.note", accent: accent) }
    /// 网易云音乐的品牌红；实底在两种外观下都配白字。
    static let accent = AccentPalette(light: 0xE60026, dark: 0xFF4D5E, lightFill: 0xE60026, darkFill: 0xE60026)
    var descriptor: ModuleDescriptor { Self.metadata }
    var libraryOrigin: LibraryOrigin { .netease }
    let store: NeteaseStore
    private let contentCache = NeteaseContentCache()
    private let onAccountChange: () -> Void
    private let onLibraryChange: () -> Void
    init(store: NeteaseStore, onAccountChange: @escaping () -> Void = {}, onLibraryChange: @escaping () -> Void = {}) {
        self.store = store; self.onAccountChange = onAccountChange; self.onLibraryChange = onLibraryChange
    }
    var accountEntry: ModuleAccountEntry? {
        .init(title: "网易云音乐", avatarURL: NeteaseArtwork.url(store.profile?.avatarUrl), isSignedIn: store.profile != nil)
    }
    func openAccount() { store.showsAccount = true }
    func dismissAccount() { store.showsAccount = false; store.showsLogin = false }
    func songActions(for track: Track, onImportLyrics: (() -> Void)?) -> AnyView? {
        guard track.remoteSource?.providerID == "netease" else { return nil }
        return AnyView(NeteasePlayerActions(track: track, onImportLyrics: onImportLyrics))
    }
    func loginView() -> AnyView? { AnyView(NeteaseLoginView(store: store)) }
    func playlistPicker(for track: Track) -> AnyView? {
        guard let id = (track.remoteSource?.itemID).flatMap(Int.init) else { return nil }
        return store.profile == nil ? loginView() : AnyView(NeteasePlaylistPicker(songID: id).environment(store))
    }
    func collectionRoute(kind: String, itemID: String) -> AppRoute? {
        guard let id = Int(itemID) else { return nil }
        switch kind {
        case "album": return .netease(.album(id))
        case "playlist": return .netease(.playlist(id))
        default: return nil
        }
    }
    func collectionRemoval(for item: MirroredCollection) -> LibraryRemoval? {
        guard !item.isPermanent, collectionRoute(kind: item.kind.rawValue, itemID: item.itemID) != nil else { return nil }
        return .account(providerID: descriptor.id.rawValue, kind: item.kind.rawValue, itemID: item.itemID,
                        notice: "网易云账号也会取消收藏此内容。")
    }
    func removeCollection(kind: String, itemID: String) async throws {
        guard let id = Int(itemID) else { throw ModuleCapabilityError.unavailable }
        switch kind {
        case "album": try await store.library.unsubscribeAlbum(id: id)
        case "playlist": try await store.library.unsubscribePlaylist(id: id)
        default: throw ModuleCapabilityError.unavailable
        }
    }
    func cachedSongActions(for track: Track, downloads: DownloadStore) -> [SongRowAction] {
        [.init(id: "download", title: "转为下载", systemImage: "arrow.down.circle") {
            Task { await downloads.enqueueNeteaseSong(track, quality: self.store.playbackSettings.quality) }
        }]
    }
    func deactivate() { contentCache.stop() }
    func rootView() -> AnyView { AnyView(NeteaseHomeView()) }
    func searchSection(query: String) -> AnyView? { AnyView(NeteaseSearchSection(query: query)) }
    func destination(for route: AppRoute) -> AnyView? {
        guard route.moduleID == .netease, let page = route.destination.base as? NeteaseRoute else { return nil }
        if case .artist(let id) = page { return AnyView(NeteaseArtistDetailView(id: id)) }
        if case .search(let query, let kind) = page { return AnyView(NeteaseSearchPage(query: query, kind: kind)) }
        return AnyView(NeteaseCollectionView(route: page))
    }
    func install(in content: AnyView) -> AnyView { AnyView(NeteaseScope(store: store, content: content, onAccountChange: onAccountChange, onLibraryChange: onLibraryChange).environment(contentCache)) }
}
private struct NeteaseScope: View {
    @Bindable var store: NeteaseStore
    let content: AnyView
    let onAccountChange: () -> Void
    let onLibraryChange: () -> Void
    var body: some View {
        content
            .sheet(isPresented: $store.showsLogin) { NeteaseLoginView(store: store) }
            .sheet(isPresented: $store.showsAccount) {
                NeteaseSettingsView(store: store)
            }
            .environment(store)
            .onChange(of: store.profile?.userId) { _, _ in onAccountChange() }
            .onChange(of: store.library.revision) { _, _ in onLibraryChange() }
    }
}
