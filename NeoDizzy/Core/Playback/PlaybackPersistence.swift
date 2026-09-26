// 移植自 MeloX（GPLv3）Core/Playback/Queue/PlaybackPersistence.swift：快照只保留 M1 用到的字段。

import Foundation

/// 下次启动时恢复的播放状态。曲目不含播放地址，播放前重新获取。
nonisolated struct PlaybackSnapshot: Codable, Sendable {
    let queue: [Track]
    let currentIndex: Int
    let progress: TimeInterval
    let repeatMode: RepeatMode
    let isShuffled: Bool
    let shuffledOrder: [Int]
}

final class PlaybackPersistence {
    private enum Key {
        static let snapshot = "player.playbackSnapshot"
    }

    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    func load() -> PlaybackSnapshot? {
        guard let data = defaults.data(forKey: Key.snapshot) else { return nil }
        return try? JSONDecoder().decode(PlaybackSnapshot.self, from: data)
    }

    func save(_ snapshot: PlaybackSnapshot) {
        guard let data = try? JSONEncoder().encode(snapshot) else { return }
        defaults.set(data, forKey: Key.snapshot)
    }

    func clear() {
        defaults.removeObject(forKey: Key.snapshot)
    }
}
