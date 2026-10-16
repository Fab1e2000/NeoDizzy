import Foundation
import Observation

/// 资料库「最近播放」：一首歌真正开始播放时记下它所在的专辑，最新的在前，最多 30 张。
@MainActor
@Observable
final class PlaybackHistoryStore {
    nonisolated struct Entry: Codable, Hashable, Identifiable, Sendable {
        enum Kind: String, Codable, Sendable { case localAlbum, neteaseAlbum, dizzylabAlbum }
        let kind: Kind
        let itemID: String
        var title: String
        var subtitle: String
        var coverURL: URL?
        var playedAt: Date
        var id: String { "\(kind.rawValue)/\(itemID)" }
    }

    static let limit = 30
    private(set) var entries: [Entry]
    @ObservationIgnored private let defaults: UserDefaults
    private static let key = "playbackHistory.v1"

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        entries = defaults.data(forKey: Self.key).flatMap { try? JSONDecoder().decode([Entry].self, from: $0) } ?? []
    }

    func record(_ track: Track, at date: Date = .now) {
        guard let (kind, itemID) = Self.album(of: track) else { return }
        let entry = Entry(kind: kind, itemID: itemID, title: track.albumTitle, subtitle: track.artists,
                          coverURL: track.coverURL, playedAt: date)
        // 同一张专辑连着播放只更新时间，不重排、不重复写入。
        if entries.first?.id == entry.id {
            entries[0].playedAt = date
        } else {
            entries.removeAll { $0.id == entry.id }
            entries.insert(entry, at: 0)
            entries = Array(entries.prefix(Self.limit))
        }
        if let data = try? JSONEncoder().encode(entries) { defaults.set(data, forKey: Self.key) }
    }

    /// 本地文件按本地专辑记；网易云按专辑 ID；两种来源都没有的是 DizzyLab 站点曲目。
    private static func album(of track: Track) -> (Entry.Kind, String)? {
        if let local = track.localSource { return (.localAlbum, local.albumID) }
        if let remote = track.remoteSource {
            guard remote.providerID == "netease", let id = Int(track.discID), id > 0 else { return nil }
            return (.neteaseAlbum, String(id))
        }
        return track.discID.isEmpty ? nil : (.dizzylabAlbum, track.discID)
    }
}
