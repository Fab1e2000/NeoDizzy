import Foundation

extension NeteaseModule {
    static var registration: PlatformRegistration {
        PlatformRegistration(descriptor: metadata) { services in
            let store = NeteaseStore()
            let library = services.offlineLibrary
            let downloads = NeteaseDownloadProvider(api: store.api, library: library)
            downloads.playlistCompleted = { [weak library] title, id, tracks in
                try await library?.savePlaylist(title: title, tracks: tracks,
                                                source: LibrarySource(provider: "netease", kind: "playlist", id: id))
            }
            services.downloads.register(downloads)
            try? FileManager.default.createDirectory(at: URL.documentsDirectory.appending(path: "netease", directoryHint: .isDirectory),
                                                     withIntermediateDirectories: true)
            let api = store.api, quality = store.playbackSettings
            services.resolver.register("netease", stream: { try await api.stream($0) }, lyrics: { try await api.lyrics($0) },
                                       cacheKey: { api.cacheKey(for: $0.id) }, selectedQuality: { quality.selected.rawValue })
            services.player.registerDiscovery("netease") { try await store.radio.next() }
            services.playbackHistory.register("netease") { track in
                guard let id = Int(track.discID), id > 0 else { return nil }
                return String(id)
            }
            services.player.reporting.register("netease", onStart: { track, source in
                store.reporter.started(track, sourceID: source)
            }, onFinish: { track, source, seconds in
                store.reporter.finished(track, sourceID: source, seconds: seconds)
            })
            quality.changed = { [weak services] in services?.player.remoteQualityDidChange(providerID: "netease") }
            store.accountChanged = { [weak services] in services?.player.remoteAccountDidChange(providerID: "netease") }
            let mirror = services.accountLibrary, favorites = services.favorites
            if let account = mirror.neteaseAccountID {
                favorites.migrate(providerID: "netease", account: String(account), tracks: mirror.neteaseLikedTracks)
            }
            favorites.register("netease", provider: FavoritesProvider(
                account: { store.profile.map { String($0.userId) } },
                load: {
                    let revision = store.revision
                    guard let userID = store.profile?.userId else { throw NeteaseError.loginRequired }
                    let songs = try await api.favoritePlaylistSongs(userID: userID)
                    guard store.revision == revision else { throw CancellationError() }
                    mirror.recordFavoriteMetadata(songs)
                    return songs.map(\.track)
                },
                setLiked: { track, liked in
                    guard let id = (track.remoteSource?.itemID).flatMap(Int.init) else { throw NeteaseError.response }
                    try await store.library.setSongLiked(id, liked)
                }))
            mirror.registerNetease(store)
            services.libraryProviders.registerNetease(store, mirror: mirror)
            let module = NeteaseModule(store: store, onAccountChange: { [weak services] in
                guard let services, services.isEnabled(.netease) else { return }
                services.favorites.updateAccounts()
                Task { await services.syncAccountLibrary(force: true) }
            }, onLibraryChange: { [weak services] in
                guard let services, services.isEnabled(.netease) else { return }
                services.accountLibrary.rebuildNetease(from: store)
            })
            return PlatformRuntime(module: module, synchronize: { [weak services] _ in
                guard let services, services.isEnabled(.netease) else { return }
                await migrateSavedItems(store: store, services: services)
            }, shutdown: {
                store.accountChanged = nil
                quality.changed = nil
                store.suspend()
                await api.client.setEnabled(false)
            })
        }
    }

    private static func migrateSavedItems(store: NeteaseStore, services: AppServices) async {
        guard store.profile != nil else { return }
        for item in services.savedLibrary.items where item.providerID == "netease" {
            guard services.isEnabled(.netease) else { return }
            guard let id = Int(item.itemID) else { services.savedLibrary.remove(id: item.id); continue }
            do {
                switch item.kind {
                case .song:
                    let track: Track
                    if let saved = item.track { track = saved }
                    else {
                        guard let song = try await store.api.songs([id]).first else { throw NeteaseError.emptyResponse }
                        track = song.track
                    }
                    try await services.favorites.setLiked(track, true)
                case .playlist:
                    let playlist = try await store.api.playlist(id)
                    if store.library.isSubscribed(playlist) != true { try await store.library.togglePlaylist(playlist) }
                case .album:
                    try await store.library.loadAlbumStatus(id)
                    if store.library.albumStates[id] != true {
                        try await store.library.toggleAlbum(NeteaseAlbum(id: id, name: item.title, picUrl: nil, artist: nil))
                    }
                }
                guard services.isEnabled(.netease) else { return }
                services.savedLibrary.remove(id: item.id)
            } catch { continue }
        }
    }
}
