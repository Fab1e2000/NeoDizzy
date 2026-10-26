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

    @Test func previousFollowsPlayOrderAndWrapsWhenRepeatingAll() {
        var queue = PlaybackQueue()
        queue.replace(with: tracks, startingAt: 0)
        #expect(queue.previousIndex(wraps: false) == nil)
        #expect(queue.previousIndex(wraps: true) == 4)
        queue.restore(tracks: tracks, currentIndex: 1, isShuffled: true, shuffledOrder: [0, 3, 1, 4, 2])
        // 随机时按随机顺序：当前是第 1 首，排在 3 后面。
        #expect(queue.previousIndex(wraps: false) == 3)
    }

    @Test(arguments: [false, true], [false, true])
    func adjacentLookupsFollowQueueAcrossEveryPosition(shuffled: Bool, wraps: Bool) {
        let order = shuffled ? [0, 3, 1, 4, 2] : Array(tracks.indices)
        for position in order.indices {
            var queue = PlaybackQueue()
            queue.restore(tracks: tracks, currentIndex: order[position], isShuffled: shuffled, shuffledOrder: order)
            let next = position + 1 < order.count ? order[position + 1] : wraps ? order[0] : nil
            let previous = position > 0 ? order[position - 1] : wraps ? order.last : nil
            #expect(queue.nextIndex(wraps: wraps) == next)
            #expect(queue.previousIndex(wraps: wraps) == previous)
            #expect(queue.canMove(by: 1, wraps: wraps) == (next != nil))
            #expect(queue.canMove(by: -1, wraps: wraps) == (previous != nil))
            let original = queue.currentIndex
            let moved = queue.move(by: 1, wraps: wraps)
            #expect(moved == (next != nil))
            #expect(queue.currentIndex == (next ?? original))
        }
    }

    @Test(arguments: [false, true])
    func adjacentLookupsExcludeCurrentEntryInEmptyAndSingleTrackQueues(shuffled: Bool) {
        var queue = PlaybackQueue()
        queue.restore(tracks: [], currentIndex: 0, isShuffled: shuffled, shuffledOrder: [])
        #expect(queue.nextIndex(wraps: true) == nil)
        #expect(queue.previousIndex(wraps: true) == nil)
        #expect(!queue.canMove(by: 1, wraps: true))
        let movedEmptyQueue = queue.move(by: -1, wraps: true)
        #expect(!movedEmptyQueue)
        queue.restore(tracks: [tracks[0]], currentIndex: 0, isShuffled: shuffled, shuffledOrder: [0])
        #expect(queue.nextIndex(wraps: true) == nil)
        #expect(queue.previousIndex(wraps: true) == nil)
        // 播放器仍可循环播放唯一条目，但相邻条目 UI 不重复展示它。
        let repeatedSingleTrack = queue.move(by: 1, wraps: true)
        #expect(repeatedSingleTrack)
        #expect(queue.currentIndex == 0)
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
    private let renewed = URL(string: "https://fixture.invalid/renewed.mp3")!
    private final class FetchLog { var discIDs: [String] = [] }
    private func resolver(log: FetchLog, localFile: @escaping (Track) -> URL?, result: URL) -> StreamResolver {
        let resolver = StreamResolver(localFile: localFile)
        resolver.register("dizzylab", provider: PlaybackProvider(stream: { track in
            log.discIDs.append(track.discID)
            return .init(url: result, expiresAt: .distantFuture, isPreview: true)
        }))
        return resolver
    }
    @Test func localFileWinsOverPreviewAndDoesNotNeedNetworkOrLogin() async throws {
        let file = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".mp3")
        try Data([1, 2, 3]).write(to: file)
        defer { try? FileManager.default.removeItem(at: file) }
        let log = FetchLog()
        let resolver = resolver(log: log, localFile: { _ in file }, result: renewed)
        #expect(try await resolver.stream(for: track(1)) == file)
        resolver.removeAll()
        #expect(try await resolver.stream(for: track(1)) == file)
        #expect(log.discIDs.isEmpty)
    }

    @Test func removedLocalFileFallsBackToNetwork() async throws {
        let missing = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".mp3")
        let log = FetchLog()
        let resolver = resolver(log: log, localFile: { _ in missing }, result: renewed)
        #expect(try await resolver.stream(for: track(1)) == renewed)
        #expect(log.discIDs == ["fx4"])
    }

    @Test func brokenLocalFileCanBeBypassedForSingleRetry() async throws {
        let file = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".mp3")
        try Data([0]).write(to: file)
        defer { try? FileManager.default.removeItem(at: file) }
        let resolver = resolver(log: FetchLog(), localFile: { _ in file }, result: renewed)
        #expect(try await resolver.stream(for: track(1), preferLocal: false) == renewed)
        #expect(try await resolver.stream(for: track(1)) == file)
    }
}

@MainActor struct PlaybackProviderIsolationTests {
    private func remote(_ provider: String) -> Track {
        var song = track(1)
        song.remoteSource = RemoteTrackSource(providerID: provider, itemID: "same-id")
        return song
    }

    @Test func emptyHostDoesNotImplicitlyCallOriginalPlatform() async {
        let resolver = StreamResolver()
        await #expect(throws: PlaybackError.unavailable) { try await resolver.stream(for: track(1)) }
        #expect(resolver.audioCacheKey(for: track(1)) == nil)
    }

    @Test func unregisteringOneSourceKeepsOtherSourceCacheAndDownloadedFiles() async throws {
        let file = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try Data([1]).write(to: file)
        defer { try? FileManager.default.removeItem(at: file) }
        var local = false
        let resolver = StreamResolver(localFile: { _ in local ? file : nil })
        var firstCalls = 0, secondCalls = 0
        let first = remote("first"), second = remote("second")
        resolver.register("first", provider: PlaybackProvider(stream: { _ in
            firstCalls += 1
            return .init(url: URL(string: "https://first.invalid/audio")!, expiresAt: .distantFuture, isPreview: false)
        }))
        resolver.register("second", provider: PlaybackProvider(stream: { _ in
            secondCalls += 1
            return .init(url: URL(string: "https://second.invalid/audio")!, expiresAt: .distantFuture, isPreview: false)
        }))
        _ = try await resolver.stream(for: first)
        let secondURL = try await resolver.stream(for: second)
        resolver.unregister("first")
        await #expect(throws: PlaybackError.unavailable) { try await resolver.stream(for: first) }
        #expect(try await resolver.stream(for: second) == secondURL)
        #expect(firstCalls == 1 && secondCalls == 1)
        local = true
        #expect(try await resolver.stream(for: first) == file)
    }

    @Test func disabledSourceCannotCommitLateResponse() async throws {
        let resolver = StreamResolver()
        let song = remote("first")
        var resume: CheckedContinuation<Void, Never>?
        resolver.register("first", provider: PlaybackProvider(stream: { _ in
            await withCheckedContinuation { resume = $0 }
            return .init(url: URL(string: "https://first.invalid/late")!, expiresAt: .distantFuture, isPreview: false)
        }))
        let task = Task { try await resolver.stream(for: song) }
        while resume == nil { await Task.yield() }
        resolver.unregister("first")
        resume?.resume()
        await #expect(throws: CancellationError.self) { try await task.value }
        await #expect(throws: PlaybackError.unavailable) { try await resolver.stream(for: song) }
    }

    @Test func localLookupReceivesRegisteredQualityOnlyForItsSource() {
        var qualities: [String?] = []
        let resolver = StreamResolver(qualityLocalFile: { _, quality in qualities.append(quality); return nil })
        resolver.register("first", provider: PlaybackProvider(stream: { _ in throw PlaybackError.unavailable }, selectedQuality: { "lossless" }))
        _ = resolver.localURL(for: remote("first"))
        _ = resolver.localURL(for: remote("second"))
        resolver.unregister("first")
        _ = resolver.localURL(for: remote("first"))
        #expect(qualities == ["lossless", nil, nil])
    }
}
