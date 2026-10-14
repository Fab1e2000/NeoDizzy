// Adapted from MeloX NeteaseAPI+Home and NeteaseAPI (GPL-3.0).
import Foundation

extension NeteaseAPI {
    func homeFeed(refresh: Bool = false) async throws -> NeteaseHomeFeed {
        struct Response: Decodable { let data: NeteaseHomeFeed }
        let value: Response = try await client.request("/api/homepage/block/page", data: ["refresh": refresh], authenticated: true)
        return value.data
    }
    func categorizedPlaylists(_ category: String, offset: Int = 0) async throws -> (items: [NeteasePlaylist], more: Bool) {
        struct Response: Decodable { let playlists: [NeteasePlaylist]; let more: Bool? }
        let value: Response = try await client.request("/api/playlist/list", data: ["cat": category, "order": "hot", "offset": offset, "limit": 30, "total": true])
        return (value.playlists, value.more ?? (value.playlists.count == 30))
    }
    func qualityPlaylists(before: Int = 0) async throws -> (items: [NeteasePlaylist], more: Bool, cursor: Int) {
        struct Response: Decodable { let playlists: [NeteasePlaylist]; let more: Bool?; let lasttime: Int? }
        let value: Response = try await client.request("/api/playlist/highquality/list", data: ["cat": "全部", "limit": 30, "lasttime": before, "total": true])
        return (value.playlists, value.more ?? false, value.lasttime ?? value.playlists.last?.updateTime ?? 0)
    }
    func topArtists() async throws -> [NeteaseArtist] {
        struct Payload: Decodable { let artists: [NeteaseArtist] }
        struct Response: Decodable { let list: Payload }
        let value: Response = try await client.request("/api/toplist/artist")
        return value.list.artists
    }
    func artist(_ id: Int) async throws -> (artist: NeteaseArtist, songs: [NeteaseSong]) {
        struct Response: Decodable { let artist: NeteaseArtist; let hotSongs: [NeteaseSong] }
        let value: Response = try await client.request("/api/v1/artist/\(id)")
        return (value.artist, value.hotSongs)
    }
    func artistAlbums(_ id: Int, offset: Int = 0) async throws -> (items: [NeteaseAlbum], more: Bool) {
        struct Response: Decodable { let hotAlbums: [NeteaseAlbum]; let more: Bool? }
        let value: Response = try await client.request("/api/artist/albums/\(id)", data: ["limit": 30, "offset": offset, "total": true])
        return (value.hotAlbums, value.more ?? (value.hotAlbums.count == 30))
    }
    func newSongs(region: NeteaseRegion) async throws -> [NeteaseSong] {
        struct Response: Decodable { let data: [NeteaseSong] }
        let value: Response = try await client.webRequest("/api/v1/discovery/new/songs", data: ["areaId": region.areaID, "total": true], readFallback: true)
        return Array(value.data.prefix(100))
    }
    func personalizedSongs() async throws -> [NeteaseSong] {
        struct Entry: Decodable { let song: NeteaseSong? }
        struct Response: Decodable { let result: [Entry] }
        let value: Response = try await client.webRequest("/api/personalized/newsong", data: ["type": "recommend", "limit": 30, "areaId": 0], readFallback: true)
        return value.result.compactMap(\.song)
    }
    func similarSongs(_ id: Int) async throws -> [NeteaseSong] {
        struct Response: Decodable { let songs: [NeteaseSong] }
        let value: Response = try await client.webRequest("/api/v1/discovery/simiSong", data: ["songid": id, "limit": 30, "offset": 0], readFallback: true)
        return value.songs
    }
}
