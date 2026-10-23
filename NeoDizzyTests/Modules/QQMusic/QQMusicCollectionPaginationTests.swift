import Foundation
import Testing
@testable import NeoDizzy

struct QQMusicCollectionPaginationTests {
    @Test(arguments: ["album", "playlist", "chart"])
    func collectionsLoadEveryAdvertisedPage(kind: String) async throws {
        let result = try await collection(kind, scenario: "complete")
        #expect(result.songs.map(\.mid) == ["song0", "song1", "song2"])
    }

    @Test(arguments: ["album", "playlist", "chart"])
    func explicitlyEmptyCollectionsRemainValid(kind: String) async throws {
        #expect(try await collection(kind, scenario: "empty").songs.isEmpty)
    }

    @Test(arguments: ["album", "playlist", "chart"])
    func truncatedOrInconsistentCollectionsCannotBeExportedAsComplete(kind: String) async throws {
        for scenario in ["truncated", "missingTotal", "booleanTotal", "negativeTotal", "fractionalTotal", "changedTotal", "overlap"] {
            await #expect(throws: QQMusicError.self) { try await collection(kind, scenario: scenario) }
        }
    }

    @Test func malformedAlbumRowsAreNotDropped() async throws {
        await #expect(throws: QQMusicError.self) { try await collection("album", scenario: "malformedWrapper") }
    }

    @Test func playlistRequiresConsistentPaginationMetadata() async throws {
        for scenario in ["missingMore", "invalidMore", "earlyEnd", "excessMore"] {
            await #expect(throws: QQMusicError.self) { try await collection("playlist", scenario: scenario) }
        }
    }

    @Test func playlistAcceptsBooleanContinuationFlag() async throws {
        #expect(try await collection("playlist", scenario: "booleanMore").songs.count == 3)
    }

    private func collection(_ kind: String, scenario: String) async throws -> QQMusicCollection {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [QQMusicCollectionProtocol.self]
        configuration.httpCookieStorage = nil
        let client = QQMusicClient(session: URLSession(configuration: configuration),
                                   credential: .init(musicID: scenario, musicKey: "synthetic-key"))
        switch kind {
        case "album": return try await client.album(mid: "testAlbum")
        case "chart": return try await client.chart(id: "1")
        default: return try await client.playlist(id: "1")
        }
    }
}

nonisolated private final class QQMusicCollectionProtocol: URLProtocol, @unchecked Sendable {
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        do {
            var body = request.httpBody ?? Data()
            if body.isEmpty, let stream = request.httpBodyStream {
                stream.open()
                defer { stream.close() }
                var buffer = [UInt8](repeating: 0, count: 4096)
                while stream.hasBytesAvailable {
                    let count = stream.read(&buffer, maxLength: buffer.count)
                    if count < 0 { throw URLError(.cannotDecodeRawData) }
                    if count == 0 { break }
                    body.append(contentsOf: buffer.prefix(count))
                }
            }
            guard let root = try JSONSerialization.jsonObject(with: body) as? [String: Any],
                  let comm = root["comm"] as? [String: Any], let scenario = comm["uin"] as? String,
                  let call = root["req_0"] as? [String: Any], let method = call["method"] as? String,
                  let param = call["param"] as? [String: Any] else { throw URLError(.badServerResponse) }
            let data = try response(method: method, param: param, scenario: scenario)
            let bytes = try JSONSerialization.data(withJSONObject: ["code": 0, "req_0": ["code": 0, "data": data]])
            client?.urlProtocol(self, didReceive: HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: bytes)
            client?.urlProtocolDidFinishLoading(self)
        } catch { client?.urlProtocol(self, didFailWithError: error) }
    }
    override func stopLoading() {}

    private func response(method: String, param: [String: Any], scenario: String) throws -> [String: Any] {
        if method == "GetAlbumDetail" { return ["basicInfo": ["title": "Test Album"]] }
        let offset = (param["begin"] ?? param["offset"] ?? param["song_begin"]) as? Int ?? -1
        guard offset == 0 || offset == 2 else { throw URLError(.badServerResponse) }
        let empty = scenario == "empty" || (scenario == "truncated" && offset > 0)
        let indices = empty ? [] : offset == 0 ? [0, 1] : [scenario == "overlap" ? 1 : 2]
        let songs: [[String: Any]] = indices.map { ["id": $0 + 1, "mid": "song\($0)", "title": "Song \($0)"] }
        var total: Any? = scenario == "empty" ? 0 : 3
        switch scenario {
        case "missingTotal": total = nil
        case "booleanTotal": total = true
        case "negativeTotal": total = -1
        case "fractionalTotal": total = 3.5
        case "changedTotal" where offset > 0: total = 4
        default: break
        }
        switch method {
        case "GetAlbumSongList":
            var data: [String: Any] = ["songList": songs.map { ["songInfo": $0] }]
            if scenario == "malformedWrapper" { data["songList"] = [["songInfo": songs[0]], ["songInfo": "invalid"]] }
            data["totalNum"] = total
            return data
        case "GetDetail":
            var info: [String: Any] = ["title": "Test Chart"]
            info["totalNum"] = total
            return ["data": info, "songInfoList": songs]
        case "CgiGetDiss":
            let more = !empty && offset == 0
            var data: [String: Any] = ["dirinfo": ["title": "Test Playlist"], "songlist": songs, "hasmore": more ? 1 : 0]
            data["total_song_num"] = total
            switch scenario {
            case "missingMore": data["hasmore"] = nil
            case "invalidMore": data["hasmore"] = 2
            case "earlyEnd": data["hasmore"] = 0
            case "excessMore": data["hasmore"] = 1
            case "booleanMore": data["hasmore"] = more
            default: break
            }
            return data
        default: throw URLError(.badServerResponse)
        }
    }
}
