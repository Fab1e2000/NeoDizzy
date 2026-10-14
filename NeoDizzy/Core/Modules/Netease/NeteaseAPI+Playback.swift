// Endpoint parameters and client-log transport follow MeloX (GPL-3.0).
import Foundation

extension NeteaseAPI {
    func intelligenceSongs(seedID: Int, playlistID: Int) async throws -> [NeteaseSong] {
        struct Item: Decodable { let id: Int }
        struct Response: Decodable { let data: [Item] }
        let response: Response = try await client.request("/api/playmode/intelligence/list", data: [
            "songId": seedID, "type": "fromPlayOne", "playlistId": playlistID,
            "startMusicId": seedID, "count": 1
        ], authenticated: true)
        let songs = try await songs(response.data.map(\.id).filter { $0 > 0 })
        guard !songs.isEmpty else { throw NeteasePlaybackError.noRecommendations }
        return songs
    }

    func reportPlayback(songID: Int, sourceID: Int, seconds: Int? = nil) async throws {
        var fields: [String: Any] = ["id": String(songID), "type": "song", "mainsite": "1",
                                     "mainsiteWeb": "1", "content": "id=\(sourceID)"]
        if let seconds {
            fields.merge(["download": 0, "end": "playend", "sourceId": String(sourceID),
                          "time": String(max(0, seconds)), "wifi": 0, "source": "list"]) { _, new in new }
        }
        let logs = try JSONSerialization.data(withJSONObject: [["action": seconds == nil ? "startplay" : "play", "json": fields]])
        struct Response: Decodable { let code: Int }
        let _: Response = try await client.request("/api/feedback/weblog",
            data: ["logs": String(decoding: logs, as: UTF8.self)], authenticated: true, clientLog: true)
    }
}

nonisolated enum NeteasePlaybackError: LocalizedError {
    case noLikes, noRecommendations
    var errorDescription: String? {
        switch self {
        case .noLikes: "请先在网易云音乐中喜欢一些歌曲，再开启心动模式。"
        case .noRecommendations: "暂时没有心动推荐，请稍后重试。"
        }
    }
}
