import Foundation
import Observation

/// 实际开始播放时记录歌曲；保留专辑历史供搜索推荐和旧封面恢复使用。
@MainActor
@Observable
final class PlaybackHistoryStore {
    nonisolated struct Entry: Codable, Hashable, Identifiable, Sendable {
        enum Kind: String, Codable, Sendable { case localAlbum, neteaseAlbum, dizzylabAlbum, remoteAlbum }
        let kind: Kind
        var sourceID: String? = nil
        let itemID: String
        var title: String
        var subtitle: String
        var coverURL: URL?
        var playedAt: Date
        var providerID: String {
            switch kind {
            case .localAlbum: "local"
            case .neteaseAlbum: "netease"
            case .dizzylabAlbum: "dizzylab"
            case .remoteAlbum: sourceID ?? ""
            }
        }
        var id: String { "\(providerID)/album/\(itemID)" }
    }

    nonisolated struct SongEntry: Codable, Identifiable, Sendable {
        let track: Track
        let playedAt: Date
        var id: String { track.id }
    }

    static let songLimit = 100
    private(set) var songs: [SongEntry]
    private static let songsKey = "playbackHistory.songs.v1"
    static let limit = 30
    private(set) var entries: [Entry]
    @ObservationIgnored private let defaults: UserDefaults
    private static let key = "playbackHistory.v1"
    @ObservationIgnored private var providers: [String: (Track) -> String?] = [:]

    func register(_ providerID: String, albumID: @escaping (Track) -> String?) { providers[providerID] = albumID }
    func unregister(_ providerID: String) { providers[providerID] = nil }

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        songs = defaults.data(forKey: Self.songsKey).flatMap { try? JSONDecoder().decode([SongEntry].self, from: $0) } ?? []
        entries = defaults.data(forKey: Self.key).flatMap { try? JSONDecoder().decode([Entry].self, from: $0) } ?? []
    }

    func record(_ track: Track, at date: Date = .now) {
        // An unregistered source must not publish late playback history.
        guard track.localSource != nil || track.playbackProviderID.map({ providers[$0] != nil }) == true else { return }
        songs.removeAll { $0.id == track.id }
        songs.insert(SongEntry(track: track, playedAt: date), at: 0)
        songs = Array(songs.prefix(Self.songLimit))
        if let data = try? JSONEncoder().encode(songs) { defaults.set(data, forKey: Self.songsKey) }

        let kind: Entry.Kind, itemID: String, sourceID: String?
        if let local = track.localSource {
            kind = .localAlbum; itemID = local.albumID; sourceID = nil
        } else {
            guard let providerID = track.playbackProviderID, let album = providers[providerID]?(track), !album.isEmpty else { return }
            kind = .remoteAlbum; itemID = album; sourceID = providerID
        }
        let entry = Entry(kind: kind, sourceID: sourceID, itemID: itemID, title: track.albumTitle, subtitle: track.artists,
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

}
