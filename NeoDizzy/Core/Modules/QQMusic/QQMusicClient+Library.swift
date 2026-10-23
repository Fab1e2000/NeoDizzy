// Contracts: L-1124/QQMusicApi modules/user.py, songlist.py, album.py (GPL-3.0-or-later).
import Foundation

extension QQMusicClient {
    func requireLibraryAccount() throws -> QQMusicCredential {
        guard enabled else { throw QQMusicError.disabled }
        guard let credential, !credential.musicID.isEmpty, credential.musicID != "0", !credential.musicKey.isEmpty else { throw QQMusicError.loginRequired }
        return credential
    }

    func likedSongs(accountID: String? = nil) async throws -> [QQMusicSong] {
        let account = try requireLibraryAccount()
        guard accountID == nil || accountID == account.musicID else { throw CancellationError() }
        let token = generation, uin = try await libraryEncryptedUIN()
        var result: [QQMusicSong] = []
        var pagination = QQMusicCollectionPagination()
        while true {
            try checkLibraryGeneration(token)
            let data = try await call("music.srfDissInfo.DissInfo", "CgiGetDiss", [
                "disstid": 0, "dirid": 201, "enc_host_uin": uin,
                "song_begin": pagination.offset, "song_num": 100, "tag": true, "userinfo": true, "orderlist": true
            ])
            let batch = try Self.dailySongs(data: data)
            let more = try Self.libraryHasMore(data)
            let finished = try pagination.append(batch, total: data["total_song_num"], hasMore: more)
            result += batch
            if finished { return result }
        }
    }

    func libraryPlaylists(accountID: String? = nil) async throws -> [QQMusicLibraryPlaylist] {
        let account = try requireLibraryAccount(), token = generation
        guard accountID == nil || accountID == account.musicID else { throw CancellationError() }
        let own = try await call("music.musicasset.PlaylistBaseRead", "GetPlaylistByUin", ["uin": account.musicID])
        guard let rows = own["v_playlist"] as? [[String: Any]],
              try QQMusicCollectionPagination.hasMore(own["bFinish"]) else { throw QQMusicError.invalidResponse }
        guard try QQMusicCollectionPagination.count(own["total"]) == rows.count else { throw QQMusicError.invalidResponse }
        var result = try rows.map { try QQMusicLibraryPlaylist(json: $0, owned: true) }
        guard Set(result.map(\.id)).count == result.count else { throw QQMusicError.invalidResponse }
        var seen = Set(result.map(\.id))
        var pagination = QQMusicLibraryPagination()
        let uin = try await libraryEncryptedUIN()
        while true {
            try checkLibraryGeneration(token)
            let data = try await call("music.musicasset.PlaylistFavRead", "CgiGetPlaylistFavInfo", ["uin": uin, "offset": pagination.offset, "size": 100])
            guard let rows = data["v_list"] as? [[String: Any]] else { throw QQMusicError.invalidResponse }
            try Self.checkLibraryListReadable(data, failedKey: "v_failTids")
            let batch = try rows.map { try QQMusicLibraryPlaylist(json: $0, owned: false) }
            let more = try Self.libraryHasMore(data)
            let finished = try pagination.append(batch.map(\.id), total: data["total"], hasMore: more)
            result += batch.filter { seen.insert($0.id).inserted }
            if finished { return result }
        }
    }

    func libraryAlbums(accountID: String? = nil) async throws -> [QQMusicLibraryAlbum] {
        let account = try requireLibraryAccount()
        guard accountID == nil || accountID == account.musicID else { throw CancellationError() }
        let token = generation, uin = try await libraryEncryptedUIN()
        var result: [QQMusicLibraryAlbum] = []
        var pagination = QQMusicLibraryPagination()
        while true {
            try checkLibraryGeneration(token)
            let data = try await call("music.musicasset.AlbumFavRead", "CgiGetAlbumFavInfo", ["euin": uin, "offset": pagination.offset, "size": 100])
            guard let rows = data["v_list"] as? [[String: Any]] else { throw QQMusicError.invalidResponse }
            try Self.checkLibraryListReadable(data, failedKey: "v_failAlbumId")
            let batch = try rows.map(QQMusicLibraryAlbum.init(json:))
            let more = try Self.libraryHasMore(data)
            let finished = try pagination.append(batch.map(\.id), total: data["total"], hasMore: more)
            result += batch
            if finished { return result }
        }
    }

    /// Official y.qq.com Web client obtains the encrypted identity from this
    /// authenticated profile response; a numeric UIN is never substituted for it.
    private func libraryEncryptedUIN() async throws -> String {
        let account = try requireLibraryAccount(), token = generation, requestID = UUID()
        // Use the same session-bound request profile as QQMusicLoginClient.validate.
        let hash = account.musicKey.utf16.reduce(UInt32(5381)) { ($0 &* 33) &+ UInt32($1) } & 0x7fff_ffff
        var url = URLComponents(string: "https://c6.y.qq.com/rsc/fcgi-bin/fcg_get_profile_homepage.fcg")!
        url.queryItems = [
            "g_tk": String(hash), "format": "json", "inCharset": "utf-8", "outCharset": "utf-8",
            "notice": "0", "cid": "205360838", "needNewCode": "0", "loginUin": account.musicID,
            "hostUin": "0", "userid": account.musicID, "reqfrom": "1"
        ].sorted { $0.key < $1.key }.map { URLQueryItem(name: $0.key, value: $0.value) }
        var request = URLRequest(url: url.url!)
        request.httpShouldHandleCookies = false
        request.setValue("https://y.qq.com/", forHTTPHeaderField: "Referer")
        request.setValue("Mozilla/5.0", forHTTPHeaderField: "User-Agent")
        request.setValue("uin=\(account.musicID); qqmusic_uin=\(account.musicID); qm_keyst=\(account.musicKey); qqmusic_key=\(account.musicKey)", forHTTPHeaderField: "Cookie")
        let task = Task { [session, request] in
            let (data, response) = try await session.data(for: request, delegate: QQMusicLibraryRedirectDelegate())
            guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode),
                  http.url?.scheme == "https", http.url?.host == "c6.y.qq.com", http.url?.path == request.url?.path else { throw QQMusicError.invalidResponse }
            return data
        }
        requests[requestID] = task
        defer { requests.removeValue(forKey: requestID) }
        let bytes = try await withTaskCancellationHandler { try await task.value } onCancel: { task.cancel() }
        try checkLibraryGeneration(token)
        guard let root = try JSONSerialization.jsonObject(with: bytes) as? [String: Any], let code = root["code"] as? Int else { throw QQMusicError.invalidResponse }
        guard code == 0 else { throw QQMusicError.server(code) }
        guard let data = root["data"] as? [String: Any], let creator = data["creator"] as? [String: Any],
              let uin = creator["encrypt_uin"] as? String, !uin.isEmpty else { throw QQMusicError.invalidResponse }
        return uin
    }

    func setSongLiked(_ song: QQMusicSong, liked: Bool, accountID: String) async throws {
        try await writeSong(song, directoryID: 201, playlistID: "0", adding: liked, accountID: accountID)
    }

    func addSong(_ song: QQMusicSong, to playlist: QQMusicLibraryPlaylist, accountID: String) async throws {
        guard playlist.isOwned, playlist.directoryID > 0, !playlist.isLiked else { throw QQMusicError.invalidResponse }
        try await writeSong(song, directoryID: playlist.directoryID, playlistID: playlist.id, adding: true, accountID: accountID)
    }

    private func writeSong(_ song: QQMusicSong, directoryID: Int, playlistID: String, adding: Bool, accountID: String) async throws {
        guard try requireLibraryAccount().musicID == accountID else { throw CancellationError() }
        guard let id = Int64(song.id), id > 0, let tid = Int64(playlistID) else { throw QQMusicError.invalidResponse }
        let data = try await call("music.musicasset.PlaylistDetailWrite", adding ? "AddSonglist" : "DelSonglist", [
            "dirId": directoryID, "tid": tid, "bFmtUtf8": true, "v_songInfo": [["songId": id, "songType": song.songType]]
        ])
        guard let code = data["retCode"] as? Int else { throw QQMusicError.invalidResponse }
        guard code == 0 else { throw QQMusicError.server(code) }
    }

    func setPlaylistSubscribed(id: String, subscribed: Bool, accountID: String) async throws {
        guard try requireLibraryAccount().musicID == accountID else { throw CancellationError() }
        guard let number = Int64(id), number > 0 else { throw QQMusicError.invalidResponse }
        let token = generation, uin = try await libraryEncryptedUIN()
        try checkLibraryGeneration(token)
        let data = try await call("music.musicasset.PlaylistFavWrite", subscribed ? "FavPlaylist" : "CancelFavPlaylist", ["uin": uin, "v_playlistId": [number]])
        try Self.checkLibraryWrite(data, failedKey: "v_failedPlaylistId")
    }

    func libraryAlbum(mid: String) async throws -> QQMusicLibraryAlbum {
        _ = try requireLibraryAccount()
        let data = try await call("music.musichallAlbum.AlbumInfoServer", "GetAlbumDetail", ["albumMId": mid])
        guard let basic = data["basicInfo"] as? [String: Any] else { throw QQMusicError.invalidResponse }
        return try QQMusicLibraryAlbum(json: basic)
    }

    func setAlbumSubscribed(_ album: QQMusicLibraryAlbum, subscribed: Bool, accountID: String) async throws {
        guard try requireLibraryAccount().musicID == accountID else { throw CancellationError() }
        let data = try await call("music.musicasset.AlbumFavWrite", subscribed ? "FavAlbum" : "CancelFavAlbum", ["v_albumId": [album.numericID]])
        try Self.checkLibraryWrite(data, failedKey: "v_failedAlbumId")
    }

    private func checkLibraryGeneration(_ token: UUID) throws {
        try Task.checkCancellation()
        guard generation == token, enabled else { throw CancellationError() }
    }

    nonisolated static func libraryHasMore(_ data: [String: Any]) throws -> Bool {
        guard let value = data["hasmore"] as? Int, value == 0 || value == 1 else { throw QQMusicError.invalidResponse }
        return value == 1
    }

    nonisolated static func checkLibraryWrite(_ data: [String: Any], failedKey: String) throws {
        guard let code = data["result"] as? Int else { throw QQMusicError.invalidResponse }
        guard code == 0 else { throw QQMusicError.server(code) }
        if let failed = data[failedKey] {
            guard let values = failed as? [Any], values.isEmpty else { throw QQMusicError.invalidResponse }
        }
    }

    nonisolated static func checkLibraryListReadable(_ data: [String: Any], failedKey: String) throws {
        if let hidden = data["hide"], try QQMusicCollectionPagination.hasMore(hidden) { throw QQMusicError.invalidResponse }
        if let failed = data[failedKey] {
            guard let values = failed as? [Any], values.isEmpty else { throw QQMusicError.invalidResponse }
        }
    }
}

nonisolated private final class QQMusicLibraryRedirectDelegate: NSObject, URLSessionTaskDelegate, @unchecked Sendable {
    func urlSession(_ session: URLSession, task: URLSessionTask, willPerformHTTPRedirection response: HTTPURLResponse,
                    newRequest request: URLRequest, completionHandler: @escaping (URLRequest?) -> Void) {
        completionHandler(nil)
    }
}

nonisolated private struct QQMusicLibraryPagination {
    private(set) var offset = 0
    private var total: Int?
    private var seen = Set<String>()
    mutating func append(_ ids: [String], total value: Any?, hasMore: Bool) throws -> Bool {
        let count = try QQMusicCollectionPagination.count(value)
        guard total == nil || total == count, Set(ids).count == ids.count, seen.isDisjoint(with: ids),
              ids.count <= count - offset else { throw QQMusicError.invalidResponse }
        total = count
        offset += ids.count
        guard !ids.isEmpty || offset == count, hasMore == (offset < count) else { throw QQMusicError.invalidResponse }
        seen.formUnion(ids)
        return offset == count
    }
}
