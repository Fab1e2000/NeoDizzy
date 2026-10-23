import Foundation

/// 专辑里的一首曲目。会写入播放队列快照，所以不包含会过期的播放地址（见 `StreamResolver`）。
nonisolated struct Track: Codable, Hashable, Identifiable, Sendable {
    /// 站点曲目的专辑 ID；纯本地曲目为空，身份使用 localSource。
    let discID: String
    /// 专辑内序号，接口返回的是字符串 `"1"`、`"2"`…，播放地址的文件名也用它。
    let number: String
    let title: String
    /// 逗号分隔的艺术家，原样保留。
    let artists: String
    let albumTitle: String
    let coverURL: URL?
    /// 能播放的时长：试听曲目是试听片段的长度，其余是完整版时长（JSON 接口没有，从专辑页 HTML 补上）。
    /// 取不到时为空。
    var duration: TimeInterval?

    /// 本地导入曲目；旧快照缺少该字段时自动恢复为 nil.
    var localSource: LocalTrackSource? = nil

    /// 新网络来源显式命名空间；两种来源均为空时兼容原有 DizzyLab 队列。
    var remoteSource: RemoteTrackSource? = nil

    var id: String { remoteSource.map { "remote/\($0.providerID)/\($0.itemID)" } ?? localSource.map { "local/\($0.trackID)" } ?? "\(discID)/\(number)" }
}

nonisolated struct LocalTrackSource: Codable, Hashable, Sendable {
    let albumID: String
    let trackID: String
}

nonisolated struct RemoteTrackSource: Codable, Hashable, Sendable {
    let providerID: String
    let itemID: String
}

// Legacy queue snapshots omit remoteSource for the original platform. Keep that
// decoding convention at the model boundary, not in the playback engine.
extension Track {
    var playbackProviderID: String? {
        remoteSource?.providerID ?? (localSource == nil ? "dizzylab" : nil)
    }
}

nonisolated struct DiscoverySelection: Sendable {
    let track: Track
    let stream: URL
    let label: String
    let tags: [String]
}
