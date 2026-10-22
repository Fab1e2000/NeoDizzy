import Foundation
import Observation

/// 在线专辑、歌单的完整曲目列表：打开过的才有，用来判断封面角标该显示「已缓存」还是「已下载」。
/// 只在详情页加载完成时记录，不为角标单独联网。
@Observable
@MainActor
final class CollectionTrackIndex {
    static let shared = CollectionTrackIndex()
    nonisolated static func key(provider: String, kind: String, id: String) -> String { "\(provider)/\(kind)/\(id)" }

    private var tracks: [String: [Track]] = [:]
    @ObservationIgnored private var order: [String] = []
    @ObservationIgnored private let file: URL
    private let capacity: Int

    init(directory: URL = URL.applicationSupportDirectory.appendingPathComponent("Library", isDirectory: true), capacity: Int = 300) {
        file = directory.appendingPathComponent("CollectionTracks.json")
        self.capacity = capacity
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        if let data = try? Data(contentsOf: file), let saved = try? JSONDecoder().decode(Snapshot.self, from: data) {
            tracks = saved.tracks; order = saved.order.filter { saved.tracks[$0] != nil }
        }
    }

    func tracks(for key: String) -> [Track]? { tracks[key] }

    func record(_ key: String, tracks list: [Track]) {
        guard !list.isEmpty, tracks[key] != list else { return }
        tracks[key] = list
        order.removeAll { $0 == key }; order.append(key)
        while order.count > capacity { tracks[order.removeFirst()] = nil }
        if let data = try? JSONEncoder().encode(Snapshot(tracks: tracks, order: order)) { try? data.write(to: file, options: .atomic) }
    }

    private struct Snapshot: Codable {
        var tracks: [String: [Track]]
        var order: [String]
    }
}

/// 一组歌曲整体能否离线播放：全部下载是「已下载」，全部下载或缓存（可以混合）是「已缓存」，否则没有。
nonisolated enum CollectionOfflineState: Equatable {
    case cached, downloaded

    static func resolve(_ tracks: [Track], isDownloaded: (Track) -> Bool, isCached: (Track) -> Bool) -> Self? {
        guard !tracks.isEmpty else { return nil }
        var allDownloaded = true
        for track in tracks where !isDownloaded(track) {
            allDownloaded = false
            if !isCached(track) { return nil }
        }
        return allDownloaded ? .downloaded : .cached
    }
}
