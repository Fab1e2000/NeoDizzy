// Endpoint parameters and client-log transport follow MeloX (GPL-3.0).
import Foundation

extension NeteaseAPI {
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
