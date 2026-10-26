import Foundation

extension AccountLibraryMirror {
    func registerQQMusic(_ store: QQMusicStore) {
        register("qqmusic", account: { [weak store] in store?.active == true ? store?.credential?.musicID : nil }) { [weak self, weak store] force in
            guard let self, let store, store.active else { return }
            try await self.syncQQMusic(store, force: force)
        }
    }
    func rebuildQQMusic(from store: QQMusicStore) {
        guard store.active, let account = store.library.accountID, state("qqmusic").account == account else { return }
        let updated = qqMusicCollections(from: store.library)
        let saved = state("qqmusic").collections
        let playlists = store.library.playlistsLoaded ? updated.filter { $0.kind == .playlist } : saved.filter { $0.kind == .playlist }
        let albums = store.library.albumsLoaded ? updated.filter { $0.kind == .album } : saved.filter { $0.kind == .album }
        replace("qqmusic", collections: playlists + albums)
    }
    func syncQQMusic(_ store: QQMusicStore, force: Bool) async throws {
        try await sync("qqmusic", account: store.active ? store.credential?.musicID : nil) { commit in
            let revision = store.revision
            // Preserve the previous mirror until both complete account lists are available.
            async let playlists: Void = store.library.loadPlaylists(force: force)
            async let albums: Void = store.library.loadAlbums(force: force)
            _ = try await (playlists, albums)
            guard store.active, store.revision == revision else { throw CancellationError() }
            try commit(self.qqMusicCollections(from: store.library))
        }
    }
    func qqMusicCollections(from library: QQMusicLibrary) -> [MirroredCollection] {
        let playlists = library.playlists.map { playlist in
            item(providerID: "qqmusic", kind: .playlist, itemID: playlist.id,
                 title: playlist.isLiked ? String(localized: "我喜欢的音乐") : playlist.title,
                 subtitle: playlist.isOwned ? String(localized: "我创建的 · \(playlist.songCount) 首") : String(localized: "QQ 音乐 · 收藏播放列表"),
                 coverURL: playlist.coverURL, isLikedPlaylist: playlist.isLiked, isPermanent: playlist.isOwned)
        }
        let albums = library.albums.map { album in
            item(providerID: "qqmusic", kind: .album, itemID: album.id, title: album.title,
                 subtitle: String(localized: "QQ 音乐"), coverURL: album.coverURL)
        }
        return playlists.filter(\.isLikedPlaylist) + playlists.filter { !$0.isLikedPlaylist } + albums
    }
}

extension FavoritesStore {
    func registerQQMusic(_ store: QQMusicStore) {
        register("qqmusic", provider: FavoritesProvider(
            account: { store.active ? store.credential?.musicID : nil },
            load: {
                let revision = store.revision
                guard store.active, store.credential != nil else { throw QQMusicError.loginRequired }
                try await store.library.loadLikes(force: true)
                guard store.active, store.revision == revision else { throw CancellationError() }
                return store.library.likedSongs.map(\.track)
            },
            setLiked: { track, liked in
                guard track.remoteSource?.providerID == "qqmusic", let mid = track.remoteSource?.itemID else { throw QQMusicError.invalidResponse }
                try await store.library.setSongLiked(mid: mid, liked)
            }))
    }
}
