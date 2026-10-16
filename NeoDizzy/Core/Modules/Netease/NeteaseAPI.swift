// Endpoint paths and parameters adapted from MeloX NeteaseAPI and NeteaseAPI+Home (GPL-3.0).
import Foundation

final class NeteaseAPI {
    let client: NeteaseClient
    let playbackSettings: NeteasePlaybackSettings
    init(client: NeteaseClient, playbackSettings: NeteasePlaybackSettings = NeteasePlaybackSettings()) {
        self.client = client
        self.playbackSettings = playbackSettings
    }

    func recommended() async throws -> [NeteasePlaylist] {
        struct Response: Decodable { let result: [NeteasePlaylist] }
        let response: Response = try await client.request("/api/personalized/playlist", data: ["limit": 30, "total": true, "n": 1000])
        return response.result
    }
    func charts() async throws -> [NeteasePlaylist] {
        struct Response: Decodable { let list: [NeteasePlaylist] }
        let response: Response = try await client.request("/api/toplist")
        return response.list
    }
    func albums(offset: Int = 0, region: NeteaseRegion = .all) async throws -> [NeteaseAlbum] {
        struct Response: Decodable { let albums: [NeteaseAlbum] }
        let response: Response = try await client.request("/api/album/new", data: ["limit": 30, "offset": offset, "total": true, "area": region.rawValue])
        return response.albums
    }
    func playlist(_ id: Int) async throws -> NeteasePlaylist {
        struct Response: Decodable { let playlist: NeteasePlaylist }
        let response: Response = try await client.request("/api/v6/playlist/detail", data: ["id": id, "n": 100, "s": 8])
        return response.playlist
    }
    func songs(_ ids: [Int]) async throws -> [NeteaseSong] {
        guard !ids.isEmpty else { return [] }
        struct Response: Decodable { let songs: [NeteaseSong] }
        let payload = try JSONSerialization.data(withJSONObject: ids.map { ["id": $0] })
        let response: Response = try await client.request("/api/v3/song/detail", data: ["c": String(decoding: payload, as: UTF8.self)])
        let byID = Dictionary(response.songs.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
        return ids.compactMap { byID[$0] }
    }
    func album(_ id: Int) async throws -> (NeteaseAlbum, [NeteaseSong]) {
        struct Response: Decodable { let album: NeteaseAlbum; let songs: [NeteaseSong] }
        let response: Response = try await client.request("/api/v1/album/\(id)")
        return (response.album, response.songs)
    }
    func daily() async throws -> [NeteaseSong] {
        struct Payload: Decodable { let dailySongs: [NeteaseSong] }
        struct Response: Decodable { let data: Payload }
        let response: Response = try await client.request("/api/v3/discovery/recommend/songs", authenticated: true)
        return response.data.dailySongs
    }
    func radio() async throws -> [NeteaseSong] {
        struct Response: Decodable { let data: [NeteaseSong] }
        let response: Response = try await client.request("/api/v1/radio/get", data: ["mode": "EXPLORE", "limit": 30], authenticated: true)
        return response.data
    }
    func profile() async throws -> NeteaseProfile {
        struct Response: Decodable { let profile: NeteaseProfile? }
        for path in ["/api/w/nuser/account/get", "/api/nuser/account/get"] {
            do {
                let response: Response = try await client.request(path, authenticated: true)
                if let profile = response.profile { return profile }
            } catch is CancellationError { throw CancellationError() }
            catch { if path == "/api/nuser/account/get" { throw error } }
        }
        throw NeteaseError.loginRequired
    }
    func userPlaylists(_ userID: Int, offset: Int = 0, limit: Int = 2000) async throws -> [NeteasePlaylist] {
        struct Response: Decodable { let playlist: [NeteasePlaylist] }
        let response: Response = try await client.request("/api/user/playlist", data: ["uid": userID, "limit": limit, "offset": offset, "includeVideo": true], authenticated: true)
        return response.playlist
    }
    /// Use the actual account playlist, matching “我的歌单 → 我喜欢的音乐”.
    func favoritePlaylistSongs(userID: Int) async throws -> [NeteaseSong] {
        let lists = try await userPlaylists(userID)
        guard let favorite = lists.first(where: { $0.specialType == 5 && $0.creator?.userId == userID }) else {
            throw NeteaseError.response
        }
        let detail = try await playlist(favorite.id)
        guard let ids = detail.trackIds?.map(\.id) else { throw NeteaseError.response }
        if let count = detail.trackCount, count != ids.count { throw NeteaseError.response }
        var result: [NeteaseSong] = []
        for start in stride(from: 0, to: ids.count, by: 400) {
            let batch = Array(ids[start..<min(start + 400, ids.count)])
            let values = try await songs(batch)
            guard values.count == batch.count else { throw NeteaseError.response }
            result += values
        }
        return result
    }
    struct SearchResult: Decodable {
        var songs: [NeteaseSong]?
        let albums: [NeteaseAlbum]?
        let playlists: [NeteasePlaylist]?
        let songCount: Int?
        let albumCount: Int?
        let playlistCount: Int?
        var artists: [NeteaseArtist]? = nil
        var artistCount: Int? = nil
    }
    func search(_ query: String, kind: Int, offset: Int = 0) async throws -> SearchResult {
        struct Response: Decodable { let result: SearchResult? }
        let response: Response = try await client.request("/api/search/get", data: ["s": query, "type": kind, "limit": 30, "offset": offset])
        var result = response.result ?? SearchResult(songs: [], albums: [], playlists: [], songCount: 0, albumCount: 0, playlistCount: 0)
        // 搜索接口的歌曲只带专辑 ID、不带封面；用歌曲详情补上，播放器和「喜欢」才有封面。
        if let songs = result.songs, songs.contains(where: { $0.album?.artworkURL == nil }) {
            let details = (try? await self.songs(songs.map(\.id))) ?? []
            let byID = Dictionary(details.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
            result.songs = songs.map { song in
                song.album?.artworkURL == nil ? byID[song.id] ?? song : song
            }
        }
        return result
    }
    func stream(_ id: String) async throws -> RemotePlaybackSource {
        struct Trial: Decodable { let start: Double?; let end: Double? }
        struct Source: Decodable { let id: Int; let url: String?; let expi: Double?; let freeTrialInfo: Trial? }
        struct Response: Decodable { let data: [Source] }
        guard let number = Int(id) else { throw NeteaseError.unavailable }
        for quality in playbackSettings.selected.fallbacks {
            var data: [String: Any] = ["ids": "[\(number)]", "level": quality.rawValue, "encodeType": "flac"]
            if quality == .immersive { data["immerseType"] = "c51" }
            let response: Response = try await client.request("/api/song/enhance/player/url/v1", data: data)
            guard let source = response.data.first(where: { $0.id == number }), let text = source.url,
                  var url = URLComponents(string: text), let scheme = url.scheme,
                  ["http", "https"].contains(scheme), url.host != nil else { continue }
            url.scheme = "https"
            guard let secureURL = url.url else { continue }
            return RemotePlaybackSource(url: secureURL, expiresAt: Date().addingTimeInterval(max(0, (source.expi ?? 300) - 30)), isPreview: source.freeTrialInfo != nil)
        }
        throw NeteaseError.unavailable
    }

    func lyrics(_ id: String) async throws -> LocalLyrics {
        struct Lyric: Decodable { let lyric: String? }
        struct Response: Decodable { let lrc: Lyric?; let tlyric: Lyric? }
        let response: Response = try await client.request("/api/song/lyric", data: ["id": id, "lv": -1, "tv": -1])
        return LocalLyrics.parse([response.lrc?.lyric, response.tlyric?.lyric].compactMap { $0 }.joined(separator: "\n"))
    }
}
