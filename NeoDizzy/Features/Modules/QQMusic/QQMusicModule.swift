import SwiftUI

final class QQMusicModule: AppModule {
    static var metadata: ModuleDescriptor { .init(id: .qqmusic, title: "QQ 音乐", systemImage: "music.note", accent: accent) }
    /// QQ 音乐的品牌绿；绿底太亮，实底上配深绿字。
    static let accent = AccentPalette(light: 0x13824D, dark: 0x31C27C, lightFill: 0x31C27C, darkFill: 0x31C27C,
                                      lightInk: 0x0B3D24, darkInk: 0x0B3D24)
    var descriptor: ModuleDescriptor { Self.metadata }
    var libraryOrigin: LibraryOrigin { .qqmusic }
    let store: QQMusicStore
    let cache = QQMusicContentCache()
    private let onLibraryChange: () -> Void
    init(store: QQMusicStore, onLibraryChange: @escaping () -> Void = {}) {
        self.store = store; self.onLibraryChange = onLibraryChange
    }

    var accountEntry: ModuleAccountEntry? {
        .init(title: "QQ 音乐", avatarURL: store.credential?.avatarURL, isSignedIn: store.credential != nil)
    }
    func openAccount() { store.showsAccount = true }
    func dismissAccount() { store.showsAccount = false }
    func deactivate() { store.deactivate(); cache.stop() }
    func songActions(for track: Track, onImportLyrics: (() -> Void)?) -> AnyView? {
        guard track.remoteSource?.providerID == "qqmusic" else { return nil }
        return AnyView(QQMusicPlayerActions(track: track, onImportLyrics: onImportLyrics))
    }
    func loginView() -> AnyView? { AnyView(QQMusicLoginView(store: store)) }
    func playlistPicker(for track: Track) -> AnyView? {
        guard track.remoteSource?.providerID == "qqmusic", let mid = track.remoteSource?.itemID else { return nil }
        return store.credential == nil ? loginView() : AnyView(QQMusicPlaylistPicker(songMid: mid).environment(store))
    }
    func collectionRemoval(for item: MirroredCollection) -> LibraryRemoval? {
        guard !item.isPermanent, collectionRoute(kind: item.kind.rawValue, itemID: item.itemID) != nil else { return nil }
        return .account(providerID: "qqmusic", kind: item.kind.rawValue, itemID: item.itemID,
                        notice: "QQ 音乐账号也会取消收藏此内容。")
    }
    func removeCollection(kind: String, itemID: String) async throws {
        switch kind {
        case "album": try await store.library.unsubscribeAlbum(id: itemID)
        case "playlist": try await store.library.unsubscribePlaylist(id: itemID)
        default: throw ModuleCapabilityError.unavailable
        }
        onLibraryChange()
    }
    func cachedSongActions(for track: Track, downloads: DownloadStore) -> [SongRowAction] {
        [.init(id: "download", title: "转为下载", systemImage: "arrow.down.circle") {
            Task { await downloads.enqueueQQMusicSong(track, quality: self.store.playbackSettings.quality) }
        }]
    }
    func rootView() -> AnyView { AnyView(QQMusicHomeView()) }
    func searchSection(query: String) -> AnyView? { AnyView(QQMusicSearchSection(query: query)) }
    func destination(for route: AppRoute) -> AnyView? {
        guard route.moduleID == .qqmusic, let page = route.destination.base as? QQMusicRoute else { return nil }
        switch page {
        case .newAlbums(let area):
            return AnyView(QQMusicNewAlbumsPage(area: area))
        case .typedSearch(let query, let kind):
            return AnyView(QQMusicSearchPage(query: query, kind: kind))
        case .recommended, .charts, .chartGroup:
            return AnyView(QQMusicBrowseView(route: page))
        default:
            return AnyView(QQMusicCollectionView(route: page))
        }
    }
    func collectionRoute(kind: String, itemID: String) -> AppRoute? {
        guard !itemID.isEmpty else { return nil }
        switch kind {
        case "album": return .qqmusic(.album(itemID))
        case "playlist": return .qqmusic(.playlist(itemID))
        case "song": return .qqmusic(.song(itemID))
        default: return nil
        }
    }
    func install(in content: AnyView) -> AnyView {
        AnyView(QQMusicScope(store: store, cache: cache, content: content, onLibraryChange: onLibraryChange))
    }
}

private struct QQMusicScope: View {
    @Bindable var store: QQMusicStore
    let cache: QQMusicContentCache
    let content: AnyView
    let onLibraryChange: () -> Void
    var body: some View {
        content.environment(store).environment(cache)
            .sheet(isPresented: $store.showsAccount) { QQMusicAccountView(store: store) }
            .onChange(of: store.library.revision) { onLibraryChange() }
    }
}

extension QQMusicModule {
    static var registration: PlatformRegistration {
        PlatformRegistration(descriptor: metadata) { services in
            let store = QQMusicStore()
            let quality = store.playbackSettings
            services.downloads.register(QQMusicDownloadProvider(api: store.api, library: services.offlineLibrary,
                cacheScope: { store.active ? store.cacheScope : nil }, sessionRevision: { store.revision }))
            services.resolver.register("qqmusic", stream: { try await store.api.stream(mid: $0, quality: quality.quality) },
                                       lyrics: { try await store.api.lyrics(mid: $0) },
                                       cacheKey: { .init(trackID: $0.id, scope: store.cacheScope, quality: quality.quality.rawValue) },
                                       selectedQuality: { quality.quality.rawValue })
            services.playbackHistory.register("qqmusic") { $0.discID.isEmpty ? nil : $0.discID }
            services.player.registerDiscovery("qqmusic") {
                guard store.active else { throw CancellationError() }
                guard store.credential != nil else { throw QQMusicError.loginRequired }
                let revision = store.revision
                let track = try await store.radio.next()
                try Task.checkCancellation()
                guard store.active, store.revision == revision else { throw CancellationError() }
                return track
            }
            quality.changed = { [weak services] in services?.player.remoteQualityDidChange(providerID: "qqmusic") }
            services.favorites.registerQQMusic(store)
            services.accountLibrary.registerQQMusic(store)
            services.libraryProviders.registerQQMusic(store)
            store.accountChanged = { [weak services, weak store] in
                guard let services, let store, services.isEnabled(.qqmusic) else { return }
                services.player.remoteAccountDidChange(providerID: "qqmusic")
                services.accountLibrary.reconcileAccount("qqmusic", account: store.credential?.musicID)
                services.favorites.updateAccounts()
                Task { await services.syncAccountLibrary(force: true) }
            }
            let module = QQMusicModule(store: store, onLibraryChange: { [weak services, weak store] in
                guard let services, let store, services.isEnabled(.qqmusic) else { return }
                services.accountLibrary.rebuildQQMusic(from: store)
            })
            return PlatformRuntime(module: module, synchronize: { _ in await store.refreshProfile() }, shutdown: {
                quality.changed = nil
                await store.shutdown()
            })
        }
    }
}
