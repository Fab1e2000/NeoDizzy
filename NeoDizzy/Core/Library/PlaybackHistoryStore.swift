import Foundation
import Observation

/// 资料库「最近播放」：一首歌真正开始播放时记下它所在的专辑，最新的在前，最多 30 张。
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

    static let limit = 30
    private(set) var entries: [Entry]
    @ObservationIgnored private let defaults: UserDefaults
    private static let key = "playbackHistory.v1"
    @ObservationIgnored private var providers: [String: (Track) -> String?] = [:]

    func register(_ providerID: String, albumID: @escaping (Track) -> String?) { providers[providerID] = albumID }
    func unregister(_ providerID: String) { providers[providerID] = nil }

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        entries = defaults.data(forKey: Self.key).flatMap { try? JSONDecoder().decode([Entry].self, from: $0) } ?? []
    }

    func record(_ track: Track, at date: Date = .now) {
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
