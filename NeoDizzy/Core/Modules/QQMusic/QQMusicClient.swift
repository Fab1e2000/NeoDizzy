import Foundation

/// Native adapter of L-1124/QQMusicApi's Web CGI contracts (GPL-3.0-or-later).
/// Each runtime owns its session and credential generation; no shared cookie jar.
actor QQMusicClient {
    let session: URLSession
    private(set) var credential: QQMusicCredential?
    private(set) var enabled = true
    private(set) var generation = UUID()
    private var credentialToken = UUID()
    var requests: [UUID: Task<Data, Error>] = [:]

    init(session: URLSession? = nil, credential: QQMusicCredential? = nil) {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.httpCookieStorage = nil
        configuration.httpShouldSetCookies = false
        configuration.urlCache = nil
        configuration.timeoutIntervalForRequest = 25
        self.session = session ?? URLSession(configuration: configuration)
        self.credential = credential
    }

    func setEnabled(_ enabled: Bool) {
        self.enabled = enabled
        invalidate()
    }

    @discardableResult
    func setCredential(_ credential: QQMusicCredential?) -> UUID {
        self.credential = credential
        credentialToken = UUID()
        invalidate()
        return credentialToken
    }

    /// Undo an adoption that its owner could not publish. A newer account change
    /// always wins; cancelling network work does not invalidate this account token.
    func restoreCredential(_ credential: QQMusicCredential?, ifCurrent token: UUID) {
        guard credentialToken == token else { return }
        setCredential(credential)
    }

    private func invalidate() {
        generation = UUID()
        requests.values.forEach { $0.cancel() }
        requests.removeAll()
    }

    func search(query: String, page: Int = 1) async throws -> [QQMusicSong] {
        let data = try await call("music.adaptor.SearchAdaptor", "do_search_v2", [
            "searchid": String(UInt64.random(in: 1...UInt64.max)), "search_type": 100,
            "page_num": 30, "query": query, "page_id": max(1, page), "highlight": 0, "grp": 1
        ])
        return try Self.searchSongs(data)
    }

    nonisolated static func searchSongs(_ data: [String: Any]) throws -> [QQMusicSong] {
        guard let body = data["body"] as? [String: Any] else { throw QQMusicError.invalidResponse }
        // General search omits the song section when there are no song matches.
        guard let value = body["item_song"] else { return [] }
        guard let section = value as? [String: Any] else { throw QQMusicError.invalidResponse }
        guard let items = section["items"] else { return [] }
        guard let rows = items as? [[String: Any]] else { throw QQMusicError.invalidResponse }
        return try rows.map(QQMusicSong.init(json:))
    }

    /// Account daily list (dirid 202); verified with the existing signed-in Web session.
    func dailySongs() async throws -> [QQMusicSong] {
        guard enabled else { throw QQMusicError.disabled }
        guard let credential, !credential.musicID.isEmpty, credential.musicID != "0", !credential.musicKey.isEmpty else { throw QQMusicError.loginRequired }
        let data = try await call("music.srfDissInfo.DissInfo", "CgiGetDiss", [
            "dirid": 202, "uinAttached": true, "enc_host_uin": credential.musicID,
            "local_time": Int(Date().timeIntervalSince1970)
        ])
        return try Self.dailySongs(data: data)
    }

    nonisolated static func dailySongs(data: [String: Any]) throws -> [QQMusicSong] {
        guard let rows = data["songlist"] as? [[String: Any]] else { throw QQMusicError.invalidResponse }
        return try rows.map { row in
            if let value = row["songInfo"] {
                guard let song = value as? [String: Any] else { throw QQMusicError.invalidResponse }
                return try QQMusicSong(json: song)
            }
            if let value = row["songinfo"] {
                guard let song = value as? [String: Any] else { throw QQMusicError.invalidResponse }
                return try QQMusicSong(json: song)
            }
            return try QQMusicSong(json: row)
        }
    }

    /// QQ's radio batch endpoint; the Web contract requires a signed-in account.
    func guessSongs() async throws -> [QQMusicSong] {
        guard enabled else { throw QQMusicError.disabled }
        guard let credential, !credential.musicID.isEmpty, credential.musicID != "0", !credential.musicKey.isEmpty else { throw QQMusicError.loginRequired }
        let data = try await call("music.radioProxy.MbTrackRadioSvr", "get_radio_track", [
            "id": 99, "num": 5, "from": 0, "scene": 0, "song_ids": []
        ])
        return try Self.guessSongs(data: data)
    }

    nonisolated static func guessSongs(data: [String: Any]) throws -> [QQMusicSong] {
        guard let tracks = data["tracks"] as? [[String: Any]] else { throw QQMusicError.invalidResponse }
        return try tracks.map(QQMusicSong.init(json:))
    }

    func radarSongs(page: Int = 1) async throws -> QQMusicRadarPage {
        guard page > 0 else { throw QQMusicError.invalidResponse }
        let data = try await call("music.recommend.TrackRelationServer", "GetRadarSong", [
            "Page": page, "ReqType": 0, "FavSongs": [], "EntranceSongs": []
        ])
        return try Self.radarSongs(data: data)
    }

    nonisolated static func radarSongs(data: [String: Any]) throws -> QQMusicRadarPage {
        guard let rows = data["VecSongs"] as? [[String: Any]], let hasMore = data["HasMore"] as? Bool else { throw QQMusicError.invalidResponse }
        let songs = try rows.map { row in
            guard let track = row["Track"] as? [String: Any] else { throw QQMusicError.invalidResponse }
            return try QQMusicSong(json: track)
        }
        return QQMusicRadarPage(items: songs, hasMore: hasMore)
    }

    func song(mid: String) async throws -> QQMusicSong {
        let data = try await call("music.pf_song_detail_svr", "get_song_detail_yqq", ["song_mid": mid])
        guard let song = data["track_info"] as? [String: Any] else { throw QQMusicError.invalidResponse }
        return try QQMusicSong(json: song)
    }

    func charts() async throws -> [QQMusicCollection] {
        try await chartGroups().flatMap(\.charts)
    }

    func chartGroups() async throws -> [QQMusicChartGroup] {
        try Self.chartGroups(data: await call("music.musicToplist.Toplist", "GetAll", [:]))
    }

    nonisolated static func chartGroups(data: [String: Any]) throws -> [QQMusicChartGroup] {
        guard let groups = data["group"] as? [[String: Any]] else { throw QQMusicError.invalidResponse }
        var seenGroups = Set<String>(), seenCharts = Set<String>()
        var result: [QQMusicChartGroup] = []
        for group in groups {
            guard let id = identifier(group["groupId"]), let title = group["groupName"] as? String,
                  let rows = group["toplist"] as? [[String: Any]] else { throw QQMusicError.invalidResponse }
            guard !seenGroups.contains(id) else { continue }
            var charts: [QQMusicCollection] = []
            for row in rows {
                // These destinations require web/MV screens rather than native song collections.
                guard (row["h5JumpUrl"] as? String ?? "").isEmpty,
                      (row["specialScheme"] as? String ?? "").isEmpty else { continue }
                guard let chartID = identifier(row["topId"]), let name = row["title"] as? String else { throw QQMusicError.invalidResponse }
                guard seenCharts.insert(chartID).inserted else { continue }
                charts.append(QQMusicCollection(id: chartID, title: name, coverURL: url(row["frontPicUrl"])))
            }
            guard !charts.isEmpty else { continue }
            seenGroups.insert(id)
            result.append(QQMusicChartGroup(id: id, title: title, charts: charts))
        }
        return result
    }

    func recommendedPlaylists(cursor: Int = 0, limit: Int = 30) async throws -> QQMusicPlaylistPage {
        guard cursor >= 0, limit > 0 else { throw QQMusicError.invalidResponse }
        let data = try await call("music.playlist.PlaylistSquare", "GetRecommendFeed", ["From": cursor, "Size": limit])
        return try Self.recommendedPlaylistPage(data: data, cursor: cursor)
    }

    nonisolated static func recommendedPlaylistPage(data: [String: Any], cursor: Int) throws -> QQMusicPlaylistPage {
        guard let rows = data["List"] as? [[String: Any]], let hasMore = data["HasMore"] as? Bool,
              let next = data["FromLimit"] as? Int, next >= 0 else { throw QQMusicError.invalidResponse }
        var seen = Set<String>(), items: [QQMusicCollection] = []
        for row in rows {
            guard let playlist = row["Playlist"] as? [String: Any], let basic = playlist["basic"] as? [String: Any],
                  let id = identifier(basic["tid"]), let title = basic["title"] as? String,
                  let cover = basic["cover"] as? [String: Any], let coverURL = cover["default_url"] as? String else { throw QQMusicError.invalidResponse }
            guard seen.insert(id).inserted else { continue }
            items.append(QQMusicCollection(id: id, title: title, coverURL: url(coverURL)))
        }
        return QQMusicPlaylistPage(items: items, nextCursor: hasMore && next > cursor ? next : nil)
    }

    nonisolated static func identifier(_ value: Any?) -> String? {
        let text: String
        if let value = value as? String { text = value }
        else if let value = value as? NSNumber, String(cString: value.objCType) != "c" { text = value.stringValue }
        else { return nil }
        guard !text.isEmpty, text.allSatisfy({ $0.isASCII && $0.isNumber }) else { return nil }
        return text
    }

    func chart(id: String) async throws -> QQMusicCollection {
        let revision = generation
        guard let number = Int(id) else { throw QQMusicError.invalidResponse }
        var tracks: [QQMusicSong] = []
        var pagination = QQMusicCollectionPagination()
        var title = "排行榜", cover: URL?
        while true {
            guard revision == generation else { throw CancellationError() }
            let data = try await call("music.musicToplist.Toplist", "GetDetail", ["topId": number, "offset": pagination.offset, "num": 100, "withTags": true])
            guard let info = data["data"] as? [String: Any], let name = info["title"] as? String else { throw QQMusicError.invalidResponse }
            title = name
            cover = Self.url(info["frontPicUrl"])
            let batch = try songs(data["songInfoList"])
            let complete = try pagination.append(batch, total: info["totalNum"])
            tracks += batch
            if complete { break }
        }
        return QQMusicCollection(id: id, title: title, coverURL: cover, songs: tracks)
    }

    func album(mid: String) async throws -> QQMusicCollection {
        let revision = generation
        let info = try await call("music.musichallAlbum.AlbumInfoServer", "GetAlbumDetail", ["albumMId": mid])
        guard let basic = info["basicInfo"] as? [String: Any], let title = (basic["title"] ?? basic["name"] ?? basic["albumName"]) as? String else { throw QQMusicError.invalidResponse }
        var tracks: [QQMusicSong] = []
        var pagination = QQMusicCollectionPagination()
        while true {
            guard revision == generation else { throw CancellationError() }
            let data = try await call("music.musichallAlbum.AlbumSongList", "GetAlbumSongList", ["albumMid": mid, "begin": pagination.offset, "num": 100])
            guard let rows = data["songList"] as? [[String: Any]] else { throw QQMusicError.invalidResponse }
            let batch = try rows.map { row -> QQMusicSong in
                guard let song = row["songInfo"] as? [String: Any] else { throw QQMusicError.invalidResponse }
                return try QQMusicSong(json: song)
            }
            let complete = try pagination.append(batch, total: data["totalNum"])
            tracks += batch
            if complete { break }
        }
        return QQMusicCollection(id: mid, title: title, coverURL: QQMusicSong.cover(albumMid: mid), songs: tracks,
                                 detailDescription: QQMusicText.detailDescription(basic))
    }

    func playlist(id: String) async throws -> QQMusicCollection {
        let revision = generation
        guard let number = Int64(id) else { throw QQMusicError.invalidResponse }
        var tracks: [QQMusicSong] = []
        var pagination = QQMusicCollectionPagination()
        var title = "歌单", cover: URL?
        var detailDescription = ""
        while true {
            guard revision == generation else { throw CancellationError() }
            let data = try await call("music.srfDissInfo.DissInfo", "CgiGetDiss", ["disstid": number, "dirid": 0, "tag": true, "song_begin": pagination.offset, "song_num": 100, "userinfo": true, "orderlist": true, "onlysonglist": false])
            guard let info = data["dirinfo"] as? [String: Any] else { throw QQMusicError.invalidResponse }
            title = (info["title"] ?? info["dirName"] ?? info["name"]) as? String ?? title
            cover = Self.url(info["picurl"] ?? info["picUrl"] ?? info["cover"])
            if pagination.offset == 0 { detailDescription = QQMusicText.detailDescription(info) }
            let batch = try Self.dailySongs(data: data)
            let more = try QQMusicCollectionPagination.hasMore(data["hasmore"])
            let complete = try pagination.append(batch, total: data["total_song_num"], hasMore: more)
            tracks += batch
            if complete { break }
        }
        return QQMusicCollection(id: id, title: title, coverURL: cover, songs: tracks,
                                 detailDescription: detailDescription)
    }

    func stream(mid: String, quality: QQMusicQuality = .standard) async throws -> RemotePlaybackSource {
        guard enabled else { throw QQMusicError.disabled }
        let revision = generation
        for candidate in quality.fallbacks {
            try Task.checkCancellation()
            guard generation == revision else { throw CancellationError() }
            do {
                let data = try await call("music.vkey.GetVkey", "UrlGetVkey", [
                    "uin": credential?.musicID ?? "0", "filename": ["\(candidate.prefix)\(mid)\(mid).\(candidate.fileExtension)"],
                    "guid": String(UInt32.random(in: 1...UInt32.max)), "songmid": [mid], "songtype": [0], "ctx": 0
                ])
                return try Self.playbackSource(data, mid: mid, quality: candidate)
            } catch QQMusicError.unavailable { continue }
            catch QQMusicError.server(let code) where code == 1000 || code == 104009 { continue }
        }
        throw credential == nil ? QQMusicError.loginRequired : QQMusicError.unavailable
    }

    nonisolated static func playbackSource(_ data: [String: Any], mid: String, quality: QQMusicQuality = .standard) throws -> RemotePlaybackSource {
        guard let info = (data["midurlinfo"] as? [[String: Any]])?.first(where: { $0["songmid"] as? String == mid }),
              let path = info["purl"] as? String, !path.isEmpty else { throw QQMusicError.unavailable }
        let base = (data["sip"] as? [String])?.first(where: { $0.hasPrefix("https://") }) ?? "https://isure.stream.qqmusic.qq.com/"
        guard let url = URL(string: path, relativeTo: URL(string: base))?.absoluteURL,
              url.scheme == "https", url.host != nil else { throw QQMusicError.invalidResponse }
        // Accept only the requested full format: no RS02/O802 previews or encrypted files.
        guard url.lastPathComponent.hasPrefix(quality.prefix), url.pathExtension.lowercased() == quality.fileExtension else { throw QQMusicError.unavailable }
        return RemotePlaybackSource(url: url, expiresAt: Date().addingTimeInterval(600), isPreview: false,
                                    actualQuality: quality.rawValue, fileExtension: quality.fileExtension)
    }

    func lyrics(mid: String) async throws -> LocalLyrics {
        // crypt=0 returns base64 UTF-8 LRC; crypt=1 is upstream's encrypted QRC path.
        let data = try await call("music.musichallSong.PlayLyricInfo", "GetPlayLyricInfo", [
            "songMid": mid, "crypt": 0, "lrc_t": 0, "qrc": 0, "qrc_t": 0,
            "trans": 1, "trans_t": 0, "roma": 0, "roma_t": 0, "type": 1, "needSingingAnnotations": false
        ])
        return try Self.decodedLyrics(data)
    }

    nonisolated static func decodedLyrics(_ data: [String: Any]) throws -> LocalLyrics {
        guard let encoded = data["lyric"] as? String else { throw QQMusicError.invalidResponse }
        func decode(_ value: String) throws -> String {
            guard let bytes = Data(base64Encoded: value), let text = String(data: bytes, encoding: .utf8) else {
                throw QQMusicError.invalidResponse
            }
            return text
        }
        let original = try decode(encoded)
        // Translation is optional. A malformed optional track must not hide the original.
        let translation = (data["trans"] as? String).flatMap { try? decode($0) } ?? ""
        var lyrics = LocalLyrics.parse([original, translation == original ? "" : translation].filter { !$0.isEmpty }.joined(separator: "\n"))
        lyrics.source = "QQ 音乐"
        return lyrics
    }

    func songs(_ value: Any?) throws -> [QQMusicSong] {
        guard let rows = value as? [[String: Any]] else { throw QQMusicError.invalidResponse }
        return try rows.map(QQMusicSong.init(json:))
    }

    nonisolated static func url(_ value: Any?) -> URL? {
        guard let text = value as? String, !text.isEmpty else { return nil }
        return URL(string: text.replacingOccurrences(of: "http://", with: "https://"))
    }

    func call(_ module: String, _ method: String, _ param: [String: Any], usesSearchEnvelope: Bool = false) async throws -> [String: Any] {
        guard enabled else { throw QQMusicError.disabled }
        try Task.checkCancellation()
        let revision = generation, requestID = UUID()
        var hash: UInt32 = 5381
        for character in (credential?.musicKey ?? "").utf16 { hash = hash &* 33 &+ UInt32(character) }
        var comm: [String: String] = ["ct": "24", "cv": "4747474", "platform": "yqq.json", "chid": "0", "uin": credential?.musicID ?? "0", "g_tk": String(hash & 0x7fffffff), "g_tk_new_20200303": String(hash & 0x7fffffff), "format": "json", "inCharset": "utf-8", "outCharset": "utf-8", "notice": "0", "need_new_code": "1"]
        if let credential { comm["authst"] = credential.musicKey; comm["tmeLoginType"] = String(credential.loginType) }
        var request = URLRequest(url: URL(string: "https://u.y.qq.com/cgi-bin/musicu.fcg")!)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("https://y.qq.com/", forHTTPHeaderField: "Referer")
        request.setValue("Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 Chrome/120.0.0.0 Safari/537.36", forHTTPHeaderField: "User-Agent")
        if let credential {
            request.setValue("uin=\(credential.musicID); qqmusic_uin=\(credential.musicID); qm_keyst=\(credential.musicKey); qqmusic_key=\(credential.musicKey)", forHTTPHeaderField: "Cookie")
        }
        let responseKey = usesSearchEnvelope ? module : "req_0"
        var envelope: [String: Any] = [responseKey: ["module": module, "method": method, "param": param]]
        if !usesSearchEnvelope { envelope["comm"] = comm }
        request.httpBody = try JSONSerialization.data(withJSONObject: envelope)
        let task = Task { [session, request] in
            let (data, response) = try await session.data(for: request)
            guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else { throw QQMusicError.invalidResponse }
            return data
        }
        requests[requestID] = task
        defer { requests.removeValue(forKey: requestID) }
        let bytes = try await withTaskCancellationHandler { try await task.value } onCancel: { task.cancel() }
        try Task.checkCancellation()
        guard enabled, revision == generation else { throw CancellationError() }
        guard let root = try JSONSerialization.jsonObject(with: bytes) as? [String: Any],
              let code = root["code"] as? Int else { throw QQMusicError.invalidResponse }
        guard code == 0 else { throw QQMusicError.server(code) }
        guard let response = root[responseKey] as? [String: Any], let subcode = response["code"] as? Int else { throw QQMusicError.invalidResponse }
        guard subcode == 0 else { throw QQMusicError.server(subcode) }
        guard let data = response["data"] as? [String: Any] else { throw QQMusicError.invalidResponse }
        return data
    }
}
