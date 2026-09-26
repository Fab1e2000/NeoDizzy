import Foundation

/// 专辑里的一首曲目。会写入播放队列快照，所以不包含会过期的播放地址（见 `StreamResolver`）。
nonisolated struct Track: Codable, Hashable, Identifiable, Sendable {
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

    var id: String { "\(discID)/\(number)" }
}
