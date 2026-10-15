// Download endpoints and fallback strategy adapted from MeloX NeteaseAPI.swift (GPL-3.0).
import Foundation

nonisolated struct NeteaseDownloadSource: Sendable {
    let url: URL
    let level: String
    let type: String
    let bitrate: Int
}

extension NeteaseAPI {
    /// 下载接口优先；播放接口回退也必须拒绝试听片段。
    func downloadSource(_ id: Int, quality: NeteaseQuality) async throws -> NeteaseDownloadSource {
        struct Source: Decodable {
            let id: Int
            let url: String?
            let level: String?
            let type: String?
            let br: Int?
            let freeTrialInfo: LibraryJSON?
        }
        struct DownloadResponse: Decodable { let data: Source? }
        struct PlaybackResponse: Decodable { let data: [Source]? }
        for download in [true, false] {
            for candidate in quality.fallbacks {
                try Task.checkCancellation()
                do {
                    var data: [String: Any] = ["level": candidate.rawValue]
                    if download { data["id"] = id }
                    else { data["ids"] = "[\(id)]"; data["encodeType"] = "flac" }
                    if candidate == .immersive { data["immerseType"] = "c51" }
                    let source: Source?
                    if download {
                        let response: DownloadResponse = try await client.request("/api/song/enhance/download/url/v1", data: data)
                        source = response.data
                    } else {
                        let response: PlaybackResponse = try await client.request("/api/song/enhance/player/url/v1", data: data)
                        source = response.data?.first { $0.id == id }
                    }
                    guard let source, source.id == id, source.freeTrialInfo == nil,
                          let text = source.url, var url = URLComponents(string: text),
                          ["https", "http"].contains(url.scheme?.lowercased() ?? ""), url.host != nil,
                          url.user == nil, url.password == nil,
                          let type = source.type?.lowercased(), (type == "ncm" || AudioFileMatcher.extensions.contains(type)),
                          let level = source.level, !level.isEmpty else { continue }
                    url.scheme = "https"
                    guard let secureURL = url.url else { continue }
                    return NeteaseDownloadSource(url: secureURL, level: level, type: type, bitrate: source.br ?? 0)
                } catch is CancellationError { throw CancellationError() }
                catch { continue }
            }
        }
        throw DownloadFailure.songUnavailable
    }

    func downloadLyrics(_ id: Int) async throws -> String? {
        struct Lyric: Decodable { let lyric: String? }
        struct Response: Decodable { let lrc: Lyric? }
        let response: Response = try await client.request("/api/song/lyric", data: ["id": id, "lv": -1])
        return response.lrc?.lyric
    }
}
