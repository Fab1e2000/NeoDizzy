import Foundation

extension AccountLibraryMirror {
    var neteaseAccountID: Int? { state("netease").account.flatMap(Int.init) }
    var neteaseLikedTracks: [Track] { state("netease").legacyLikes }
    var neteaseCollections: [MirroredCollection] { state("netease").collections }
    func registerNetease(_ store: NeteaseStore) {
        register("netease", account: { [weak store] in store?.profile.map { String($0.userId) } }) { [weak self, weak store] force in
            guard let self, let store else { return }
            try await self.syncNetease(store, force: force)
        }
    }
    func rebuildNetease(from store: NeteaseStore) { rebuildNetease(from: store.library) }
    func rebuildNetease(from library: NeteaseLibrary) {
        guard library.userID == neteaseAccountID, library.userID != nil else { return }
        let updated = neteaseCollections(from: library)
        let playlists = library.playlistsLoaded ? updated.filter { $0.kind == .playlist } : neteaseCollections.filter { $0.kind == .playlist }
        let albums = library.albumsLoaded ? updated.filter { $0.kind == .album } : neteaseCollections.filter { $0.kind == .album }
        replace("netease", collections: playlists + albums)
    }
    func syncNetease(_ store: NeteaseStore, force: Bool) async throws {
        try await sync("netease", account: store.profile.map { String($0.userId) }) { commit in
            var failure: Error?
            let library = store.library
            do {
                try await library.loadPlaylists(force: force)
                let playlists = self.neteaseCollections(from: library).filter { $0.kind == .playlist }
                try commit(playlists + self.neteaseCollections.filter { $0.kind == .album })
            } catch { failure = error }
            try Task.checkCancellation()
            do {
                try await library.loadAlbums(force: force)
                let albums = self.neteaseCollections(from: library).filter { $0.kind == .album }
                try commit(self.neteaseCollections.filter { $0.kind == .playlist } + albums)
            } catch { failure = error }
            if let failure { throw failure }
        }
    }
    func recordFavoriteMetadata(_ songs: [NeteaseSong]) {
        for song in songs {
            for artist in song.artists where artist.id > 0 {
                snapshot.providers["netease", default: State()].artistIDs[artist.name] = String(artist.id)
            }
        }
        save()
    }
    func neteaseArtistID(named name: String) -> Int? { state("netease").artistIDs[name].flatMap(Int.init) }
    func artistAvatar(_ id: Int) -> URL? { state("netease").artistAvatars[String(id)] }
    func loadArtistAvatar(_ id: Int, api: NeteaseAPI) async {
        let key = "netease/\(id)"
        guard artistAvatar(id) == nil, avatarRequests.insert(key).inserted else { return }
        defer { avatarRequests.remove(key) }
        let account = state("netease").account
        let generation = generation(for: "netease")
        guard let url = try? await api.artist(id).artist.artworkURL,
              state("netease").account == account, self.generation(for: "netease") == generation,
              !Task.isCancelled else { return }
        snapshot.providers["netease", default: State()].artistAvatars[String(id)] = url
        save()
    }
    func neteaseCollections(from library: NeteaseLibrary) -> [MirroredCollection] {
        let playlists = library.playlists.map { playlist in
            let own = playlist.creator?.userId == library.userID
            let liked = own && playlist.specialType == 5
            let subtitle = liked ? String(localized: "网易云 · \(playlist.trackCount ?? 0) 首")
                : own ? String(localized: "我创建的 · \(playlist.trackCount ?? 0) 首")
                : String(localized: "收藏 · \(playlist.creator?.nickname ?? "网易云")")
            return item(providerID: "netease", kind: .playlist, itemID: String(playlist.id),
                        title: liked ? String(localized: "我喜欢的音乐") : playlist.name, subtitle: subtitle,
                        coverURL: playlist.artworkURL, isLikedPlaylist: liked, isPermanent: own)
        }
        // 「我喜欢的音乐」永远排在最前。
        let ordered = playlists.filter(\.isLikedPlaylist) + playlists.filter { !$0.isLikedPlaylist }
        let albums = library.albums.map { album in
            item(providerID: "netease", kind: .album, itemID: String(album.id), title: album.name,
                 subtitle: album.artist?.name ?? String(localized: "网易云"), coverURL: album.artworkURL)
        }
        return ordered + albums
    }

}
