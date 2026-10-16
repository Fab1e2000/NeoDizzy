// Endpoints and parameters adapted from MeloX NeteaseAPI (GPL-3.0),
// 1fe5fbab3f554e8529c4847fc54281a472b7b61a. All requests go directly to NetEase.
import Foundation

extension NeteaseAPI {
    private struct Status: Decodable { let code: Int }
    func likedSongIDs(userID: Int) async throws -> [Int] {
        struct Response: Decodable { let ids: [Int] }
        let value: Response = try await client.request("/api/song/like/get", data: ["uid": userID], authenticated: true)
        return value.ids
    }
    func setSongLiked(_ id: Int, liked: Bool) async throws {
        let _: Status = try await client.request("/api/radio/like", data: ["alg": "itembased", "trackId": id, "like": liked, "time": "3"], authenticated: true)
    }
    func setPlaylistSubscribed(_ id: Int, subscribed: Bool) async throws {
        // The official website's playlist_fav-add/del uses WEAPI with id + csrf_token.
        // Do not retry this write through another transport after an ambiguous response.
        let _: Status = try await client.webRequest(subscribed ? "/api/playlist/subscribe" : "/api/playlist/unsubscribe",
                                                   data: ["id": id], authenticated: true)
    }
    func addSong(_ id: Int, to playlistID: Int) async throws {
        let path = "/api/v1/playlist/manipulate/tracks"
        let result: Status = try await client.request(path, data: ["op": "add", "pid": playlistID, "trackIds": "[\"\(id)\"]", "imme": "true"], authenticated: true, acceptedCodes: [200, 512])
        if result.code == 512 {
            let _: Status = try await client.request(path, data: ["op": "add", "pid": playlistID, "trackIds": "[\"\(id)\",\"\(id)\"]", "imme": "true"], authenticated: true)
        }
    }
    func subscribedAlbums() async throws -> [NeteaseAlbum] {
        struct Response: Decodable { let data: [NeteaseAlbum]? }
        let value: Response = try await client.webRequest("/api/album/sublist", data: ["limit": 2000, "offset": 0, "total": true], authenticated: true, readFallback: true)
        return value.data ?? []
    }
    func albumSubscribed(_ id: Int) async throws -> Bool {
        struct Response: Decodable { let isSub: Bool? }
        let value: Response = try await client.webRequest("/api/album/detail/dynamic", data: ["id": id], authenticated: true, readFallback: true)
        return value.isSub ?? false
    }
    func setAlbumSubscribed(_ id: Int, subscribed: Bool) async throws {
        let _: Status = try await client.webRequest(subscribed ? "/api/album/sub" : "/api/album/unsub", data: ["id": id], authenticated: true)
    }
    func recentSongs() async throws -> [NeteaseSong] {
        struct Entry: Decodable { let data: NeteaseSong? }
        struct Payload: Decodable { let list: [Entry] }
        struct Response: Decodable { let data: Payload? }
        let value: Response = try await client.webRequest("/api/play-record/song/list", data: ["limit": 100], authenticated: true, readFallback: true)
        return value.data?.list.compactMap(\.data) ?? []
    }
}
