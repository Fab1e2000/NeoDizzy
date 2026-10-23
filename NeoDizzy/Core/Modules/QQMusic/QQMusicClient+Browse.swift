import Foundation

extension QQMusicClient {
    /// Search uses the upstream mobile method, with the module-keyed envelope
    /// also used by Simple Music. A Web comm envelope returns false empty pages.
    func search(query: String, kind: QQMusicSearchKind, page: Int = 1) async throws -> QQMusicBrowsePage {
        guard page > 0 else { throw QQMusicError.invalidResponse }
        let data = try await call("music.search.SearchCgiService", "DoSearchForQQMusicMobile", [
            "searchid": String(UInt64.random(in: 1...UInt64.max)), "query": query,
            "search_type": kind.rawValue, "num_per_page": 30, "page_num": page,
            "highlight": 0, "grp": 1, "selectors": [:], "vec_selectors": []
        ], usesSearchEnvelope: true)
        return try Self.typedSearch(data, kind: kind, page: page)
    }

    nonisolated static func typedSearch(_ data: [String: Any], kind: QQMusicSearchKind, page: Int) throws -> QQMusicBrowsePage {
        guard let body = data["body"] as? [String: Any], let meta = data["meta"] as? [String: Any],
              let next = meta["nextpage"] as? Int,
              let rows = body[kind.responseKey] as? [[String: Any]] else { throw QQMusicError.invalidResponse }
        var result = QQMusicBrowsePage(nextPage: next > page && !rows.isEmpty ? next : nil)
        switch kind {
        case .songs: result.songs = try rows.map(QQMusicSong.init(json:))
        case .albums: result.albums = try rows.map(QQMusicAlbum.init(json:))
        case .artists: result.artists = try rows.map(QQMusicArtist.init(json:))
        case .playlists:
            result.playlists = try rows.map { row in
                guard let id = identifier(row["dissid"] ?? row["id"]),
                      let title = (row["dissname"] ?? row["title"]) as? String else { throw QQMusicError.invalidResponse }
                return QQMusicCollection(id: id, title: QQMusicText.clean(title), coverURL: QQMusicText.url(row["logo"] ?? row["picurl"]))
            }
        }
        return result
    }

    func artist(mid: String) async throws -> QQMusicArtist {
        let data = try await call("music.musichallSinger.SingerInfoInter", "GetSingerDetail", [
            "singer_mids": [mid], "group_singer": 1, "wiki_singer": 1, "ex_singer": 1, "pic": 1, "photos": 0
        ])
        guard let rows = data["singer_list"] as? [[String: Any]],
              let row = rows.first(where: { ($0["basic_info"] as? [String: Any])?["singer_mid"] as? String == mid }),
              let basic = row["basic_info"] as? [String: Any] else { throw QQMusicError.invalidResponse }
        var artist = try QQMusicArtist(json: basic)
        artist.biography = (row["ex_info"] as? [String: Any])?["desc"] as? String ?? ""
        return artist
    }

    func artistSongs(mid: String, offset: Int = 0) async throws -> QQMusicBrowsePage {
        let data = try await call("musichall.song_list_server", "GetSingerSongList", [
            "singerMid": mid, "order": 1, "number": 30, "begin": offset
        ])
        guard let rows = data["songList"] as? [[String: Any]], let total = data["totalNum"] as? Int else { throw QQMusicError.invalidResponse }
        let songs = try rows.map { row in
            guard let json = row["songInfo"] as? [String: Any] else { throw QQMusicError.invalidResponse }
            return try QQMusicSong(json: json)
        }
        return QQMusicBrowsePage(songs: songs, nextOffset: Self.followingOffset(offset, count: rows.count, total: total))
    }

    func artistAlbums(mid: String, offset: Int = 0) async throws -> QQMusicBrowsePage {
        let data = try await call("music.musichallAlbum.AlbumListServer", "GetAlbumList", [
            "singerMid": mid, "order": 0, "number": 30, "begin": offset
        ])
        return try Self.albumPage(data, key: "albumList", offset: offset)
    }

    func newAlbums(area: Int = 1, offset: Int = 0) async throws -> QQMusicBrowsePage {
        guard (1...6).contains(area) else { throw QQMusicError.invalidResponse }
        let data = try await call("newalbum.NewAlbumServer", "get_new_album_info", ["area": area, "num": 30, "start": offset])
        return try Self.albumPage(data, key: "albums", offset: offset)
    }

    nonisolated static func albumPage(_ data: [String: Any], key: String, offset: Int) throws -> QQMusicBrowsePage {
        guard let rows = data[key] as? [[String: Any]], let total = data["total"] as? Int else { throw QQMusicError.invalidResponse }
        return QQMusicBrowsePage(albums: try rows.map(QQMusicAlbum.init(json:)), nextOffset: followingOffset(offset, count: rows.count, total: total))
    }

    func artists(offset: Int = 0, page: Int = 1) async throws -> QQMusicBrowsePage {
        let data = try await call("music.musichallSinger.SingerList", "GetSingerListIndex", [
            "area": -100, "sex": -100, "genre": -100, "index": -100, "sin": offset, "cur_page": page
        ])
        guard let rows = data["singerlist"] as? [[String: Any]], let total = data["total"] as? Int else { throw QQMusicError.invalidResponse }
        return QQMusicBrowsePage(artists: try rows.map(QQMusicArtist.init(json:)), nextOffset: Self.followingOffset(offset, count: rows.count, total: total))
    }

    func similarSongs(mid: String) async throws -> [QQMusicSong] {
        let revision = generation
        let song = try await song(mid: mid)
        guard revision == generation else { throw CancellationError() }
        guard let id = Int64(song.id) else { throw QQMusicError.invalidResponse }
        let data = try await call("music.recommend.TrackRelationServer", "GetSimilarSongs", ["songid": id])
        guard let rows = data["vecSong"] as? [[String: Any]] else { throw QQMusicError.invalidResponse }
        return try rows.map { row in
            guard let track = row["track"] as? [String: Any] else { throw QQMusicError.invalidResponse }
            return try QQMusicSong(json: track)
        }
    }

    nonisolated private static func followingOffset(_ offset: Int, count: Int, total: Int) -> Int? {
        count > 0 && offset + count < total ? offset + count : nil
    }
}
