// 移植自 MeloX（GPLv3）Core/Playback/Queue/PlaybackPersistence.swift：快照只保留 M1 用到的字段。

import Foundation

/// 下次启动时恢复的播放状态。曲目不含播放地址，播放前重新获取。
nonisolated struct PlaybackSnapshot: Codable, Sendable {
    let queue: [Track]
    let currentIndex: Int
    var progress: TimeInterval
    let repeatMode: RepeatMode
    let isShuffled: Bool
    let shuffledOrder: [Int]
    var isDiscovery: Bool? = nil
    var sourceID: Int? = nil
    var automaticContinuation: Bool? = nil
    var crossfadeEnabled: Bool? = nil
    /// Associates lightweight progress checkpoints with this exact queue snapshot.
    /// Older snapshots omit the field and retain their original progress until upgraded.
    var persistenceGeneration: UUID? = nil
}

final class PlaybackPersistence {
    enum ProgressSaveResult: Equatable {
        case saved
        case needsSnapshot
        case superseded
        case invalidProgress
    }

    private enum Key {
        static let snapshot = "player.playbackSnapshot"
        static let generation = "player.playbackSnapshotGeneration"
        static let progress = "player.playbackProgress"
    }

    private struct ProgressCheckpoint: Codable {
        let generation: UUID
        let progress: TimeInterval
    }

    private let defaults: UserDefaults
    private var generation: UUID?
    private var legacySnapshotData: Data?

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    func load() -> PlaybackSnapshot? {
        generation = nil
        legacySnapshotData = nil
        guard let data = defaults.data(forKey: Key.snapshot),
              var snapshot = try? JSONDecoder().decode(PlaybackSnapshot.self, from: data) else { return nil }
        generation = snapshot.persistenceGeneration
        guard let generation else {
            legacySnapshotData = data
            return snapshot
        }
        // The UUID inside the full snapshot is authoritative, including after a
        // process exits between the full-snapshot and generation-marker writes.
        if let data = defaults.data(forKey: Key.progress),
           let checkpoint = try? JSONDecoder().decode(ProgressCheckpoint.self, from: data),
           checkpoint.generation == generation,
           checkpoint.progress.isFinite, checkpoint.progress >= 0 {
            snapshot.progress = checkpoint.progress
        }
        return snapshot
    }

    func save(_ snapshot: PlaybackSnapshot) {
        // If encoding fails, subsequent ticks must not attach this new queue's
        // progress to the previously persisted queue.
        self.generation = nil
        legacySnapshotData = nil
        var stored = snapshot
        let generation = UUID()
        stored.persistenceGeneration = generation
        guard let data = try? JSONEncoder().encode(stored) else { return }
        defaults.set(data, forKey: Key.snapshot)
        defaults.set(generation.uuidString, forKey: Key.generation)
        defaults.removeObject(forKey: Key.progress)
        self.generation = generation
    }

    /// Periodic ticks need only persist progress, not encode every track again.
    /// All callers run on the main actor; a superseded owner cannot write a
    /// checkpoint for a replacement queue or request a fallback full save.
    func saveProgress(_ progress: TimeInterval) -> ProgressSaveResult {
        guard progress.isFinite, progress >= 0 else { return .invalidProgress }
        guard let generation else {
            if let legacySnapshotData,
               defaults.data(forKey: Key.snapshot) == legacySnapshotData {
                return .needsSnapshot
            }
            return .superseded
        }
        guard defaults.string(forKey: Key.generation) == generation.uuidString else { return .superseded }
        let checkpoint = ProgressCheckpoint(generation: generation, progress: progress)
        guard let data = try? JSONEncoder().encode(checkpoint) else { return .invalidProgress }
        defaults.set(data, forKey: Key.progress)
        return .saved
    }

    func clear() {
        defaults.removeObject(forKey: Key.snapshot)
        defaults.removeObject(forKey: Key.generation)
        defaults.removeObject(forKey: Key.progress)
        generation = nil
        legacySnapshotData = nil
    }
}
