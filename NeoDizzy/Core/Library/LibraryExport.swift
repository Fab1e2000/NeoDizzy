import Foundation

/// 可移植的资料库清单；只导出明确列出的元数据，不序列化账号、音频地址或沙盒路径。
nonisolated struct LibraryExport: Codable {
    var format = "NeoDizzyLibrary"
    var version = 1
    let exportedAt: Date
    var favorites: [Song]
    var savedSongs: [Song]
    var collections: [Collection]

    struct Song: Codable {
        let providerID: String
        let itemID: String
        let title: String
        let artists: String
        let albumTitle: String
        let albumID: String
        let number: String
        let duration: Double?
        let addedAt: Date?
        init(_ track: Track, addedAt: Date? = nil) {
            let identity = FavoriteSong(track: track)
            providerID = identity.providerID
            itemID = Self.portableID(identity.itemID)
            title = track.title; artists = track.artists; albumTitle = track.albumTitle
            albumID = Self.portableID(track.discID); number = track.number
            duration = track.duration; self.addedAt = addedAt
        }
        static func portableID(_ id: String) -> String {
            id.hasPrefix("/") || id.hasPrefix("file:") ? URL(fileURLWithPath: id).lastPathComponent : id
        }
    }
    struct Collection: Codable {
        let providerID: String
        let kind: String
        let itemID: String
        let title: String
        let subtitle: String
        var songs: [Song]
        /// 未能拉取完整列表时保留条目，并明确说明缺失，不能把空数组伪装成空歌单。
        var songsComplete: Bool
        var issue: String?
    }

    func data() throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        encoder.dateEncodingStrategy = .iso8601
        return try encoder.encode(self)
    }

    @MainActor static func snapshot(favorites: FavoritesStore, mirror: AccountLibraryMirror,
                                   saved: SavedLibraryStore, offline: OfflineLibraryStore) -> LibraryExport {
        let localAlbums = offline.visibleAlbums.map { album in
            Collection(providerID: "local", kind: "album", itemID: Song.portableID(album.id), title: album.title,
                       subtitle: album.artist, songs: album.tracks.map { Song($0) }, songsComplete: true)
        }
        let localPlaylists = offline.localPlaylists.map { playlist in
            Collection(providerID: playlist.source?.provider ?? "local", kind: "localPlaylist",
                       itemID: playlist.source?.id ?? playlist.fileURL.lastPathComponent, title: playlist.title,
                       subtitle: "本地歌单", songs: playlist.tracks.map { Song($0) }, songsComplete: true)
        }
        let remote = (mirror.neteaseCollections + mirror.dizzyLabAlbums).filter { !$0.isLikedPlaylist }.map { item in
            Collection(providerID: item.providerID, kind: item.kind.rawValue, itemID: item.itemID,
                       title: item.title, subtitle: item.subtitle, songs: [], songsComplete: false)
        }
        let keys = Set(remote.map { "\($0.providerID)/\($0.kind)/\($0.itemID)" })
        let manual = saved.items.filter { $0.kind != .song && !keys.contains("\($0.providerID)/\($0.kind.rawValue)/\($0.itemID)") }.map { item in
            Collection(providerID: item.providerID, kind: item.kind.rawValue, itemID: item.itemID,
                       title: item.title, subtitle: item.subtitle, songs: [], songsComplete: false)
        }
        return LibraryExport(exportedAt: .now, favorites: favorites.songs.map { Song($0.track, addedAt: $0.addedAt) },
                             savedSongs: saved.items.compactMap { item in item.track.map { Song($0, addedAt: item.addedAt) } },
                             collections: localAlbums + localPlaylists + remote + manual)
    }

    /// 逐个补齐在线集合；单项失败不会丢掉其他集合，文件内标记不完整项。
    @MainActor mutating func loadOnlineSongs(netease: NeteaseStore, progress: (Int, Int) -> Void) async throws {
        let revision = netease.revision
        let indices = collections.indices.filter { !collections[$0].songsComplete }
        for (position, index) in indices.enumerated() {
            try Task.checkCancellation()
            guard netease.revision == revision else { throw CancellationError() }
            progress(position + 1, indices.count)
            let item = collections[index]
            do {
                let tracks: [Track]
                if item.providerID == "netease", let id = Int(item.itemID) {
                    if item.kind == "playlist" {
                        let playlist = try await netease.api.playlist(id)
                        let ids = playlist.trackIds?.map(\.id) ?? playlist.tracks?.map(\.id) ?? []
                        guard !ids.isEmpty || (playlist.trackCount ?? 0) == 0 else { throw NeteaseError.emptyResponse }
                        var songs: [NeteaseSong] = []
                        for start in stride(from: 0, to: ids.count, by: 400) {
                            try Task.checkCancellation()
                            songs += try await netease.api.songs(Array(ids[start..<min(start + 400, ids.count)]))
                        }
                        guard songs.count == ids.count else { throw NeteaseError.emptyResponse }
                        tracks = songs.map(\.track)
                    } else { tracks = try await netease.api.album(id).1.map(\.track) }
                } else if item.providerID == "dizzylab", item.kind == "album" {
                    tracks = try await DizzyAPI.shared.discDetail(id: item.itemID).tracks
                } else { throw NeteaseError.response }
                guard netease.revision == revision else { throw CancellationError() }
                collections[index].songs = tracks.map { Song($0) }
                collections[index].songsComplete = true
            } catch is CancellationError { throw CancellationError() }
            catch { collections[index].issue = "未能读取完整歌曲列表，请联网后重新导出。" }
        }
    }
}
