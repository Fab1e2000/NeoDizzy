import Foundation
import Testing
@testable import NeoDizzy

@MainActor struct PlaybackPersistenceTests {
    private func withDefaults(_ body: (UserDefaults) throws -> Void) throws {
        let suite = "PlaybackPersistenceTests.\(UUID())"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        try body(defaults)
    }

    private func snapshot(index: Int = 1, progress: Double = 12) -> PlaybackSnapshot {
        let tracks = (0..<4).map {
            Track(discID: "album", number: "\($0)", title: "Track \($0)", artists: "Artist",
                  albumTitle: "Album", coverURL: nil,
                  localSource: .init(albumID: "album", trackID: "\($0)"))
        }
        return .init(queue: tracks, currentIndex: index, progress: progress,
                     repeatMode: .all, isShuffled: true, shuffledOrder: [1, 3, 0, 2],
                     isDiscovery: false, sourceID: 42)
    }

    @Test func progressCheckpointRestoresWithoutRewritingQueueData() throws {
        try withDefaults { defaults in
            let persistence = PlaybackPersistence(defaults: defaults)
            let original = snapshot()
            persistence.save(original)
            let queueData = try #require(defaults.data(forKey: "player.playbackSnapshot"))
            for progress in [22.0, 32.0, 42.5] {
                #expect(persistence.saveProgress(progress) == .saved)
                #expect(defaults.data(forKey: "player.playbackSnapshot") == queueData)
            }
            let restored = try #require(PlaybackPersistence(defaults: defaults).load())
            #expect(restored.progress == 42.5)
            #expect(restored.queue == original.queue)
            #expect(restored.currentIndex == original.currentIndex)
            #expect(restored.repeatMode == original.repeatMode)
            #expect(restored.isShuffled == original.isShuffled)
            #expect(restored.shuffledOrder == original.shuffledOrder)
            #expect(restored.isDiscovery == original.isDiscovery)
            #expect(restored.sourceID == original.sourceID)
        }
    }

    @Test func legacyLoadIsReadOnlyAndRequestsOneFullSnapshot() throws {
        try withDefaults { defaults in
            let original = snapshot()
            let data = try JSONEncoder().encode(original)
            defaults.set(data, forKey: "player.playbackSnapshot")
            let persistence = PlaybackPersistence(defaults: defaults)
            let restored = try #require(persistence.load())
            #expect(restored.progress == original.progress)
            #expect(restored.queue == original.queue)
            #expect(persistence.saveProgress(22) == .needsSnapshot)
            #expect(defaults.data(forKey: "player.playbackSnapshot") == data)
            #expect(defaults.object(forKey: "player.playbackSnapshotGeneration") == nil)
            persistence.save(restored)
            #expect(persistence.saveProgress(22) == .saved)
            #expect(PlaybackPersistence(defaults: defaults).load()?.progress == 22)
        }
    }

    @Test func replacementRejectsOldOwnerAndDoesNotReuseItsCheckpoint() throws {
        try withDefaults { defaults in
            let old = PlaybackPersistence(defaults: defaults)
            old.save(snapshot())
            #expect(old.saveProgress(22) == .saved)
            let current = PlaybackPersistence(defaults: defaults)
            current.save(snapshot(index: 3, progress: 5))
            #expect(old.saveProgress(32) == .superseded)
            #expect(current.load()?.progress == 5)
            #expect(current.saveProgress(15) == .saved)
            #expect(old.saveProgress(42) == .superseded)
            let restored = try #require(PlaybackPersistence(defaults: defaults).load())
            #expect(restored.currentIndex == 3)
            #expect(restored.progress == 15)
        }
    }

    @Test func clearingRevokesBothLoadedAndSavedOwners() throws {
        try withDefaults { defaults in
            let first = PlaybackPersistence(defaults: defaults)
            first.save(snapshot())
            let second = PlaybackPersistence(defaults: defaults)
            _ = second.load()
            #expect(first.saveProgress(22) == .saved)
            second.clear()
            #expect(first.saveProgress(32) == .superseded)
            #expect(second.saveProgress(32) == .superseded)
            #expect(first.load() == nil)
            #expect(defaults.object(forKey: "player.playbackProgress") == nil)
            #expect(defaults.object(forKey: "player.playbackSnapshotGeneration") == nil)
        }
    }

    @Test func replacedOrClearedLegacySnapshotCannotRequestFallbackSave() throws {
        try withDefaults { defaults in
            defaults.set(try JSONEncoder().encode(snapshot()), forKey: "player.playbackSnapshot")
            let legacy = PlaybackPersistence(defaults: defaults)
            _ = legacy.load()
            let replacement = PlaybackPersistence(defaults: defaults)
            replacement.save(snapshot(index: 2, progress: 1))
            #expect(legacy.saveProgress(22) == .superseded)
            replacement.clear()
            #expect(legacy.saveProgress(32) == .superseded)
            #expect(PlaybackPersistence(defaults: defaults).saveProgress(1) == .superseded)
        }
    }

    @Test func interruptedSnapshotReplacementDoesNotMixQueueAndProgress() throws {
        try withDefaults { defaults in
            let first = PlaybackPersistence(defaults: defaults)
            first.save(snapshot())
            #expect(first.saveProgress(22) == .saved)
            let oldMarker = try #require(defaults.string(forKey: "player.playbackSnapshotGeneration"))
            let oldCheckpoint = try #require(defaults.data(forKey: "player.playbackProgress"))
            let replacement = PlaybackPersistence(defaults: defaults)
            replacement.save(snapshot(index: 3, progress: 5))
            // Simulate termination after the full JSON was written but before
            // its marker and the prior progress checkpoint were updated.
            defaults.set(oldMarker, forKey: "player.playbackSnapshotGeneration")
            defaults.set(oldCheckpoint, forKey: "player.playbackProgress")
            let restored = PlaybackPersistence(defaults: defaults)
            let state = try #require(restored.load())
            #expect(state.currentIndex == 3)
            #expect(state.progress == 5)
            #expect(restored.saveProgress(15) == .superseded)
            // The player's normal load/resume path saves its full queue once,
            // re-establishing checkpoint ownership without repairing stale IDs.
            restored.save(state)
            #expect(restored.saveProgress(15) == .saved)
            #expect(PlaybackPersistence(defaults: defaults).load()?.progress == 15)
        }
    }

    @Test func invalidProgressAndFailedFullSavePreserveLastValidState() throws {
        try withDefaults { defaults in
            let persistence = PlaybackPersistence(defaults: defaults)
            persistence.save(snapshot())
            #expect(persistence.saveProgress(22) == .saved)
            for invalid in [Double.nan, .infinity, -.infinity, -1] {
                #expect(persistence.saveProgress(invalid) == .invalidProgress)
            }
            #expect(PlaybackPersistence(defaults: defaults).load()?.progress == 22)
            persistence.save(snapshot(index: 3, progress: .nan))
            #expect(persistence.saveProgress(32) == .superseded)
            let restored = try #require(PlaybackPersistence(defaults: defaults).load())
            #expect(restored.currentIndex == 1)
            #expect(restored.progress == 22)
        }
    }

    @Test func corruptCheckpointFallsBackToFullSnapshotProgress() throws {
        try withDefaults { defaults in
            let persistence = PlaybackPersistence(defaults: defaults)
            persistence.save(snapshot())
            defaults.set(Data("invalid checkpoint".utf8), forKey: "player.playbackProgress")
            #expect(PlaybackPersistence(defaults: defaults).load()?.progress == 12)
            defaults.set(Data("invalid snapshot".utf8), forKey: "player.playbackSnapshot")
            #expect(persistence.load() == nil)
            #expect(persistence.saveProgress(22) == .superseded)
        }
    }
}
