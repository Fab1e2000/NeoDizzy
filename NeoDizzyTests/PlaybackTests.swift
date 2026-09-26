import Foundation
import Testing
@testable import NeoDizzy

private func track(_ number: Int, disc: String = "fx4") -> Track {
    Track(discID: disc, number: String(number), title: "Track \(number)", artists: "", albumTitle: "", coverURL: nil)
}

struct PlaybackQueueTests {
    private let tracks = (1...5).map { track($0) }

    @Test func movesThroughQueueAndStopsAtEndsWithoutWrapping() {
        var queue = PlaybackQueue()
        queue.replace(with: tracks, startingAt: 3)
        #expect(queue.currentTrack?.number == "4")
        let movedToLast = queue.move(by: 1, wraps: false)
        #expect(movedToLast)
        #expect(queue.currentTrack?.number == "5")
        #expect(!queue.canMove(by: 1, wraps: false))
        let movedPastEnd = queue.move(by: 1, wraps: false)
        #expect(!movedPastEnd)
        #expect(queue.currentTrack?.number == "5")
    }

    @Test func wrapsAroundWhenRepeatingAll() {
        var queue = PlaybackQueue()
        queue.replace(with: tracks, startingAt: 4)
        let wrappedForward = queue.move(by: 1, wraps: true)
        #expect(wrappedForward)
        #expect(queue.currentTrack?.number == "1")
        let wrappedBackward = queue.move(by: -1, wraps: true)
        #expect(wrappedBackward)
        #expect(queue.currentTrack?.number == "5")
    }

    @Test func upcomingFollowsPlayOrderAndWrapsWhenRepeatingAll() {
        var queue = PlaybackQueue()
        queue.replace(with: tracks, startingAt: 2)
        #expect(queue.upcomingIndices(wraps: false) == [3, 4])
        #expect(queue.upcomingIndices(wraps: true) == [3, 4, 0, 1])
    }

    @Test func selectingFromQueueKeepsShuffleOrder() {
        var queue = PlaybackQueue()
        queue.restore(tracks: tracks, currentIndex: 0, isShuffled: true, shuffledOrder: [0, 3, 1, 4, 2])
        #expect(queue.upcomingIndices(wraps: false) == [3, 1, 4, 2])
        let selected = queue.select(index: 4)
        #expect(selected)
        #expect(queue.currentTrack?.number == "5")
        // 随机顺序不变，只是当前位置跳到了第 4 个。
        #expect(queue.upcomingIndices(wraps: false) == [2])
        #expect(queue.persistedShuffleOrder == [0, 3, 1, 4, 2])
    }

    @Test func shuffleStartsFromCurrentTrackAndVisitsEveryTrackOnce() {
        var queue = PlaybackQueue()
        queue.replace(with: tracks, startingAt: 2)
        queue.toggleShuffle()
        #expect(queue.isShuffled)
        #expect(queue.currentTrack?.number == "3")

        var visited = [queue.currentTrack!.number]
        while queue.move(by: 1, wraps: false) {
            visited.append(queue.currentTrack!.number)
        }
        #expect(visited.count == 5)
        #expect(Set(visited) == Set(tracks.map(\.number)))
    }

    @Test func restoreKeepsValidShuffleOrderAndRepairsBrokenOne() {
        var queue = PlaybackQueue()
        queue.restore(tracks: tracks, currentIndex: 1, isShuffled: true, shuffledOrder: [4, 1, 0, 3, 2])
        #expect(queue.position == 1)
        let moved = queue.move(by: 1, wraps: false)
        #expect(moved)
        #expect(queue.currentTrack?.number == "1")

        var broken = PlaybackQueue()
        broken.restore(tracks: tracks, currentIndex: 9, isShuffled: true, shuffledOrder: [0, 0])
        #expect(broken.currentTrack?.number == "5")
        #expect(broken.persistedShuffleOrder.count == 5)
        #expect(broken.persistedShuffleOrder.first == 4)
    }

    @Test func snapshotRoundTripsWithoutStreamURLs() throws {
        let snapshot = PlaybackSnapshot(
            queue: tracks,
            currentIndex: 2,
            progress: 12.5,
            repeatMode: .all,
            isShuffled: false,
            shuffledOrder: []
        )
        let data = try JSONEncoder().encode(snapshot)
        let decoded = try JSONDecoder().decode(PlaybackSnapshot.self, from: data)
        #expect(decoded.queue == tracks)
        #expect(decoded.repeatMode == .all)
        #expect(!String(decoding: data, as: UTF8.self).contains("streaming.dizzylab.net"))
    }
}

struct StreamResolverTests {
    /// 过期时间 2026-09-26 17:38（东八区）。
    private let signed = URL(string: "https://streaming.dizzylab.net/202609261738/47b9396aaf5e70bc3fc219be690419bd/fx4/preview/1.mp3")!
    private let renewed = URL(string: "https://streaming.dizzylab.net/202609261838/0f0f0f0f0f0f0f0f0f0f0f0f0f0f0f0f/fx4/preview/1.mp3")!
    private var expiry: Date { DizzyURL.streamExpiry(signed)! }

    private final class FetchLog {
        var discIDs: [String] = []
    }

    private func resolver(now: Date, log: FetchLog, result: [String: URL]) -> StreamResolver {
        StreamResolver(
            fetch: { discID in
                log.discIDs.append(discID)
                return result
            },
            now: { now }
        )
    }

    @Test func usesAddressFromDiscPageWhileFresh() async throws {
        let log = FetchLog()
        let resolver = resolver(now: expiry.addingTimeInterval(-600), log: log, result: ["1": renewed])
        resolver.store(["1": signed], for: "fx4")
        #expect(try await resolver.stream(for: track(1)) == signed)
        #expect(log.discIDs.isEmpty)
    }

    @Test func refetchesShortlyBeforeExpiry() async throws {
        let log = FetchLog()
        let resolver = resolver(now: expiry.addingTimeInterval(-60), log: log, result: ["1": renewed])
        resolver.store(["1": signed], for: "fx4")
        #expect(try await resolver.stream(for: track(1)) == renewed)
        #expect(log.discIDs == ["fx4"])
    }

    @Test func refetchesAfterPlaybackFailure() async throws {
        let log = FetchLog()
        let resolver = resolver(now: expiry.addingTimeInterval(-600), log: log, result: ["1": renewed])
        resolver.store(["1": signed], for: "fx4")
        resolver.invalidate(discID: "fx4")
        #expect(try await resolver.stream(for: track(1)) == renewed)
        #expect(log.discIDs == ["fx4"])
    }

    @Test func missingTrackIsUnavailable() async {
        let resolver = resolver(now: expiry, log: FetchLog(), result: ["1": renewed])
        await #expect(throws: PlaybackError.unavailable) {
            try await resolver.stream(for: track(7))
        }
    }
}
