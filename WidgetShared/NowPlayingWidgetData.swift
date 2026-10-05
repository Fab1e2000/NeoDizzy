import Foundation

/// 主 App 与「正在播放」小组件共用的数据：当前歌曲的信息和缩小后的封面，放在 App Group 容器里。
///
/// 小组件不能联网取封面也不能读主 App 的沙盒，所以由主 App 在换歌时写好，再通知小组件刷新。
/// 侧载时签名工具若没有保留 App Group，容器取不到，小组件只显示「未在播放」。
nonisolated enum NowPlayingWidgetData {
    static let appGroup = "group.com.elsterlee.NeoDizzy"
    static let widgetKind = "NowPlayingCover"

    struct Snapshot: Codable, Equatable, Sendable {
        let trackID: String
        let title: String
        let artists: String
        let hasArtwork: Bool
    }

    private static var folder: URL? {
        FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: appGroup)?
            .appending(path: "NowPlaying", directoryHint: .isDirectory)
    }
    private static var snapshotURL: URL? { folder?.appending(path: "snapshot.json") }
    private static var artworkURL: URL? { folder?.appending(path: "artwork.jpg") }

    static func load() -> Snapshot? {
        guard let url = snapshotURL, let data = try? Data(contentsOf: url) else { return nil }
        return try? JSONDecoder().decode(Snapshot.self, from: data)
    }

    static func loadArtwork() -> Data? {
        guard load()?.hasArtwork == true, let url = artworkURL else { return nil }
        return try? Data(contentsOf: url)
    }

    /// 传 nil 表示没有在播放，清掉旧的歌曲和封面。
    static func save(_ snapshot: Snapshot?, artwork: Data?) throws {
        guard let folder, let snapshotURL, let artworkURL else { throw CocoaError(.fileNoSuchFile) }
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        if let artwork {
            try artwork.write(to: artworkURL, options: .atomic)
        } else {
            try? FileManager.default.removeItem(at: artworkURL)
        }
        if let snapshot {
            try JSONEncoder().encode(snapshot).write(to: snapshotURL, options: .atomic)
        } else {
            try? FileManager.default.removeItem(at: snapshotURL)
        }
    }
}
