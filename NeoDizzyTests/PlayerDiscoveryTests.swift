import Foundation
import Testing
@testable import NeoDizzy

@Suite(.serialized) @MainActor struct PlayerDiscoveryTests {
    private final class Source {
        var calls = 0
        var pending: CheckedContinuation<DiscoverySelection, Error>?
        func fetch() async throws -> DiscoverySelection {
            calls += 1
            pending?.resume(throwing: CancellationError())
            return try await withCheckedThrowingContinuation { pending = $0 }
        }
        func finish(_ value: DiscoverySelection) { pending?.resume(returning: value); pending = nil }
        func fail() { pending?.resume(throwing: PlaybackError.unavailable); pending = nil }
    }
    private struct Rig {
        let player: PlayerStore
        let source: Source
        let persistence: PlaybackPersistence
        let defaults: UserDefaults
        let suite: String
        let file: URL
        func selection(_ number: Int) -> DiscoverySelection {
            DiscoverySelection(track: Track(discID: "test", number: String(number), title: "Track \(number)", artists: "", albumTitle: "Test", coverURL: nil), stream: file, label: "Test", tags: [])
        }
        func clean() { player.play([selection(1).track], startAt: 0); player.pause(); source.fail(); defaults.removePersistentDomain(forName: suite); try? FileManager.default.removeItem(at: file) }
    }
    private func rig() throws -> Rig {
        let suite = "PlayerDiscoveryTests.\(UUID())"
        let defaults = try #require(UserDefaults(suiteName: suite))
        let persistence = PlaybackPersistence(defaults: defaults)
        let source = Source()
        let file = FileManager.default.temporaryDirectory.appendingPathComponent("\(UUID()).wav")
        var data = Data()
        func text(_ string: String) { data.append(Data(string.utf8)) }
        func u16(_ value: UInt16) { var value = value.littleEndian; withUnsafeBytes(of: &value) { data.append(contentsOf: $0) } }
        func u32(_ value: UInt32) { var value = value.littleEndian; withUnsafeBytes(of: &value) { data.append(contentsOf: $0) } }
        text("RIFF"); u32(480036); text("WAVEfmt "); u32(16); u16(1); u16(1); u32(8000); u32(16000); u16(2); u16(16); text("data"); u32(480000); data.append(Data(count: 480000))
        try data.write(to: file)
        let resolver = StreamResolver(localFile: { _ in file })
        resolver.register("dizzylab", provider: PlaybackProvider(stream: { _ in throw PlaybackError.unavailable }))
        let player = PlayerStore(resolver: resolver, persistence: persistence)
        player.registerDiscoverySelection("dizzylab") { try await source.fetch() }
        return Rig(player: player, source: source, persistence: persistence, defaults: defaults, suite: suite, file: file)
    }
    private func waitFor(_ condition: () -> Bool) async throws {
        for _ in 0..<200 {
            if condition() { return }
            try await Task.sleep(for: .milliseconds(10))
        }
        Issue.record("Timed out waiting for player state")
    }
    @Test func ordinaryQueueNaturallyAdvancesWithoutLoadingAgain() async throws {
        let r = try rig(); defer { r.clean() }
        var starts: [String] = []
        r.player.reporting.onStart = { track, _ in starts.append(track.number) }
        r.player.play([r.selection(1).track, r.selection(2).track], startAt: 0)
        try await waitFor { r.player.duration > 0 && !r.player.isLoading }
        try await Task.sleep(for: .milliseconds(150))
        #expect(starts == ["1"])
        r.player.seek(to: r.player.duration - 0.15)
        try await waitFor { r.player.currentTrack?.number == "2" }
        #expect(r.player.isPlaying)
        #expect(r.player.progress < 2)
        #expect(r.persistence.load()?.currentIndex == 1)
        try await waitFor { starts == ["1", "2"] && r.player.progress > 0.2 && r.player.reporting.listenedSeconds > 0.2 }
    }

    @Test func periodicProgressRestoresWithoutRewritingTheQueueSnapshot() async throws {
        let r = try rig(); defer { r.clean() }
        r.player.play([r.selection(1).track, r.selection(2).track], startAt: 0)
        try await waitFor { r.player.duration > 0 && !r.player.isLoading }
        let original = try #require(r.defaults.data(forKey: "player.playbackSnapshot"))
        let reader = PlaybackPersistence(defaults: r.defaults)
        let deadline = ContinuousClock.now.advanced(by: .seconds(15))
        while (reader.load()?.progress ?? 0) < 10, ContinuousClock.now < deadline {
            try await Task.sleep(for: .milliseconds(100))
        }
        let saved = try #require(reader.load())
        #expect(saved.progress >= 10)
        #expect(saved.progress <= r.player.progress)
        #expect(saved.currentIndex == 0)
        #expect(saved.queue.map(\.id) == [r.selection(1).track.id, r.selection(2).track.id])
        #expect(r.defaults.data(forKey: "player.playbackSnapshot") == original)
    }

    @Test func repeatOneNaturallyReplaysWithNewReportingSession() async throws {
        let r = try rig(); defer { r.clean() }
        var starts: [String] = []
        r.player.reporting.onStart = { track, _ in starts.append(track.number) }
        r.player.play([r.selection(1).track, r.selection(2).track], startAt: 0)
        r.player.cycleRepeatMode(); r.player.cycleRepeatMode()
        try await waitFor { r.player.duration > 0 && !r.player.isLoading }
        try await Task.sleep(for: .milliseconds(150))
        r.player.seek(to: r.player.duration - 0.15)
        try await waitFor { starts.count == 2 }
        #expect(starts == ["1", "1"])
        #expect(r.player.currentTrack?.number == "1")
        #expect(r.player.isPlaying && r.player.progress < 2)
    }

    @Test func changingQueueOrderReplacesPreparedSuccessor() async throws {
        let r = try rig(); defer { r.clean() }
        r.player.play([r.selection(1).track, r.selection(2).track, r.selection(3).track], startAt: 0)
        try await waitFor { r.player.duration > 0 && !r.player.isLoading }
        r.player.moveUpcomingQueueItems(fromOffsets: IndexSet(integer: 1), toOffset: 0)
        try await Task.sleep(for: .milliseconds(150))
        r.player.seek(to: r.player.duration - 0.15)
        try await waitFor { r.player.currentTrack?.number == "3" }
        #expect(r.player.isPlaying)
    }

    @Test func disablingQueuedProviderPreservesCurrentSourceAndRevokesPreparedAudio() async throws {
        let r = try rig(); defer { r.clean() }
        let resolver = StreamResolver()
        for id in ["source-a", "source-b"] {
            resolver.register(id, provider: PlaybackProvider(stream: { _ in
                RemotePlaybackSource(url: r.file, expiresAt: .distantFuture, isPreview: false)
            }))
        }
        func track(_ source: String) -> Track {
            Track(discID: "test", number: source, title: source, artists: "", albumTitle: "", coverURL: nil,
                  remoteSource: .init(providerID: source, itemID: "1"))
        }
        let player = PlayerStore(resolver: resolver, persistence: r.persistence)
        defer { player.pause() }
        var starts: [String] = []
        player.reporting.onStart = { track, _ in starts.append(track.number) }
        player.play([track("source-a"), track("source-b")], startAt: 0)
        try await waitFor { player.queuedNextTrack?.number == "source-b" && player.duration > 0 }
        await player.disableProvider(providerID: "source-b")
        #expect(player.currentTrack?.number == "source-a" && player.isPlaying)
        #expect(player.queuedNextTrack == nil)
        player.seek(to: player.duration - 0.15)
        try await waitFor { player.issue != nil }
        #expect(!starts.contains("source-b"))
    }

    @Test func disabledQueuedProviderCannotInsertLateUncooperativeResponse() async throws {
        let r = try rig(); defer { r.clean() }
        let resolver = StreamResolver()
        resolver.register("source-a", provider: PlaybackProvider(stream: { _ in
            RemotePlaybackSource(url: r.file, expiresAt: .distantFuture, isPreview: false)
        }))
        resolver.register("source-b", provider: PlaybackProvider(stream: { _ in
            _ = try await r.source.fetch() // Deliberately ignores task cancellation until resumed.
            return RemotePlaybackSource(url: r.file, expiresAt: .distantFuture, isPreview: false)
        }))
        func track(_ source: String) -> Track {
            Track(discID: "test", number: source, title: source, artists: "", albumTitle: "", coverURL: nil,
                  remoteSource: .init(providerID: source, itemID: "1"))
        }
        let player = PlayerStore(resolver: resolver, persistence: r.persistence)
        defer { player.pause() }
        player.play([track("source-a"), track("source-b")], startAt: 0)
        try await waitFor { r.source.calls == 1 && player.duration > 0 }
        await player.disableProvider(providerID: "source-b")
        r.source.finish(r.selection(2))
        try await Task.sleep(for: .milliseconds(100))
        #expect(player.queuedNextTrack == nil)
        #expect(player.currentTrack?.number == "source-a" && player.isPlaying)
        #expect(player.issue == nil)
    }

    @Test func testNextRequestsNewTrackPreviousReturnsHistoryBeyondThreeSeconds() async throws {
        let r = try rig(); defer { r.clean() }
        r.player.playDiscovery(r.selection(1), autoplay: false)
        #expect(!(r.player.canPlayPrevious))
        #expect(r.player.canPlayNext)
        r.player.next(); r.player.next()
        try await waitFor { r.source.calls == 1 }
        #expect(!(r.player.canPlayNext))
        r.source.finish(r.selection(2))
        try await waitFor { r.player.currentTrack?.number == "2" }
        #expect(!(r.player.isPlaying))
        r.player.seek(to: 10)
        let callsBeforePrevious = r.source.calls
        r.player.previous()
        #expect(r.player.currentTrack?.number == "1")
        #expect(r.player.progress == 0)
        r.player.next()
        try await waitFor { r.source.calls > callsBeforePrevious }
        r.source.finish(r.selection(3))
        try await waitFor { r.player.currentTrack?.number == "3" }
        r.player.previous()
        #expect(r.player.currentTrack?.number == "1")
    }
    @Test func testOrdinaryAlbumRejectsLateDiscoveryResponse() async throws {
        let r = try rig(); defer { r.clean() }
        r.player.playDiscovery(r.selection(1), autoplay: false)
        r.player.next()
        try await waitFor { r.source.pending != nil }
        r.player.play([r.selection(8).track, r.selection(9).track], startAt: 0)
        r.player.pause()
        r.source.finish(r.selection(2))
        try await Task.sleep(for: .milliseconds(100))
        #expect(r.player.currentTrack?.number == "8")
        #expect(!(r.player.isDiscovery))
        r.player.next()
        #expect(r.player.currentTrack?.number == "9")
        #expect(r.source.calls == 1)
    }
    @Test func testPreviousCancelsPendingNext() async throws {
        let r = try rig(); defer { r.clean() }
        r.player.playDiscovery(r.selection(1), autoplay: false)
        r.player.next(); try await waitFor { r.source.pending != nil }
        r.source.finish(r.selection(2)); try await waitFor { r.player.currentTrack?.number == "2" }
        r.player.next(); try await waitFor { r.source.pending != nil }
        r.player.previous()
        r.source.finish(r.selection(3))
        try await Task.sleep(for: .milliseconds(100))
        #expect(r.player.currentTrack?.number == "1")
        #expect(r.player.canPlayNext)
    }
    @Test func testFailurePreservesHistoryAndCanRetry() async throws {
        let r = try rig(); defer { r.clean() }
        r.player.playDiscovery(r.selection(1), autoplay: false)
        r.player.next(); try await waitFor { r.source.pending != nil }
        r.source.fail(); try await waitFor { r.player.canPlayNext }
        #expect(r.player.currentTrack?.number == "1")
        #expect(r.player.issue?.contains("获取下一首失败") == true)
        r.player.next(); try await waitFor { r.source.calls == 2 }
        r.source.finish(r.selection(2)); try await waitFor { r.player.currentTrack?.number == "2" }
        #expect(r.player.issue == nil)
    }
    @Test func testPauseDuringRequestAndRestoreDiscoveryMode() async throws {
        let r = try rig(); defer { r.clean() }
        r.player.playDiscovery(r.selection(1))
        r.player.next(); try await waitFor { r.source.pending != nil }
        r.player.pause()
        r.source.finish(r.selection(2)); try await waitFor { r.player.currentTrack?.number == "2" }
        #expect(!(r.player.isPlaying))
        r.player.saveState()
        let restored = PlayerStore(persistence: r.persistence)
        restored.restore()
        #expect(restored.isDiscovery && restored.canPlayPrevious && restored.canPlayNext)
        #expect(restored.currentTrack?.number == "2")
        #expect(!(restored.isPlaying))
    }
    @Test func testRemoteDiscoveryUsesRegisteredSourceAndIgnoresLateResponseAfterAlbumPlay() async throws {
        let rig = try rig()
        defer { rig.clean() }
        rig.player.registerDiscovery("netease") { try await rig.source.fetch().track }
        rig.player.playRemoteDiscovery(rig.selection(1).track, providerID: "netease")
        rig.player.next()
        try await waitFor { rig.source.calls == 1 }
        rig.source.finish(rig.selection(2))
        try await waitFor { rig.player.currentTrack?.number == "2" }
        #expect(rig.player.isDiscovery)
        rig.player.next()
        try await waitFor { rig.source.calls == 2 }
        rig.player.play([rig.selection(9).track], startAt: 0)
        rig.source.finish(rig.selection(3))
        try await Task.sleep(for: .milliseconds(30))
        #expect(rig.player.currentTrack?.number == "9")
        #expect(!(rig.player.isDiscovery))
    }

    @Test func testRemoteDiscoveryAutomaticallyRequestsNextWhenAudioEnds() async throws {
        let rig = try rig()
        defer { rig.clean() }
        rig.player.registerDiscovery("netease") { try await rig.source.fetch().track }
        rig.player.playRemoteDiscovery(rig.selection(1).track, providerID: "netease")
        try await waitFor { rig.player.duration > 0 && !rig.player.isLoading }
        rig.player.seek(to: rig.player.duration - 0.1)
        try await waitFor { rig.source.calls == 1 }
        rig.source.finish(rig.selection(2))
        try await waitFor { rig.player.currentTrack?.number == "2" }
        #expect(rig.player.isPlaying)
        try await waitFor { rig.player.progress > 0.2 && rig.player.reporting.listenedSeconds > 0.2 }
    }

    @Test func testDizzyPreparesAudioBeforeNextIsTapped() async throws {
        let r = try rig(); defer { r.clean() }
        r.player.playDiscovery(r.selection(1), autoplay: false)
        try await waitFor { r.source.calls == 1 }
        #expect(r.player.currentTrack?.number == "1")
        #expect(r.player.canPlayNext)
        r.source.finish(r.selection(2))
        try await waitFor { r.player.bufferedDiscoveryTrack?.number == "2" }
        #expect(r.player.currentTrack?.number == "1")
        r.player.next()
        try await waitFor { r.player.currentTrack?.number == "2" }
        #expect(!(r.player.isPlaying))
    }

    @Test func testRemotePreparesStreamAndAudioBeforeNextIsTapped() async throws {
        let r = try rig(); defer { r.clean() }
        let resolver = StreamResolver()
        var requests: [String] = []
        resolver.register("netease", stream: { id in
            requests.append(id)
            return RemotePlaybackSource(url: r.file, expiresAt: .now.addingTimeInterval(600), isPreview: false)
        }, lyrics: { _ in throw PlaybackError.unavailable })
        let player = PlayerStore(resolver: resolver, persistence: r.persistence)
        func remote(_ id: String) -> Track {
            Track(discID: "remote", number: id, title: id, artists: "", albumTitle: "",
                  coverURL: nil, remoteSource: RemoteTrackSource(providerID: "netease", itemID: id))
        }
        var number = 1
        player.registerDiscovery("netease") { number += 1; return remote(String(number)) }
        player.playRemoteDiscovery(remote("1"), providerID: "netease")
        defer { player.play([r.selection(1).track], startAt: 0); player.pause() }
        try await waitFor { player.queuedNextTrack?.number == "2" }
        #expect(requests == ["1", "2"])
        #expect(player.currentTrack?.number == "1")
        player.next()
        try await waitFor { player.currentTrack?.number == "2" }
        #expect(requests.filter { $0 == "2" }.count == 1)
        try await waitFor { player.progress > 0.2 && player.reporting.listenedSeconds > 0.2 }
        player.remoteAccountDidChange(providerID: "netease")
        #expect(player.queuedNextTrack == nil)
    }

    @Test func legacyPlaybackStateRestoresQueueAndDropsRetiredModeOnSave() throws {
        let r = try rig(); defer { r.clean() }
        let tracks = [r.selection(1).track, r.selection(2).track]
        let snapshot = PlaybackSnapshot(queue: tracks, currentIndex: 1, progress: 12,
            repeatMode: .all, isShuffled: false, shuffledOrder: [], sourceID: 42)
        var legacy = try #require(JSONSerialization.jsonObject(with: JSONEncoder().encode(snapshot)) as? [String: Any])
        legacy["heartMode"] = true
        r.defaults.set(try JSONSerialization.data(withJSONObject: legacy), forKey: "player.playbackSnapshot")
        let restored = PlayerStore(persistence: r.persistence)
        restored.restore()
        #expect(restored.currentTrack == tracks[1])
        #expect(restored.progress == 12)
        #expect(!restored.isPlaying && !restored.isDiscovery)
        restored.pause()
        #expect(r.persistence.load()?.queue == tracks)
        #expect(r.persistence.load()?.sourceID == 42)
        let saved = try #require(r.defaults.data(forKey: "player.playbackSnapshot"))
        let object = try #require(JSONSerialization.jsonObject(with: saved) as? [String: Any])
        #expect(object["heartMode"] == nil)
    }

    @Test func normalPlaybackAdvancesThroughMixedProviders() async throws {
        let r = try rig(); defer { r.clean() }
        let resolver = StreamResolver(localFile: { _ in r.file })
        for provider in ["netease", "qqmusic"] {
            resolver.register(provider, stream: { _ in .init(url: r.file, expiresAt: .distantFuture, isPreview: false) },
                              lyrics: { _ in .parse("") })
        }
        let player = PlayerStore(resolver: resolver, persistence: r.persistence)
        let tracks = ["netease", "qqmusic"].map { provider in
            Track(discID: "album", number: "1", title: provider, artists: "", albumTitle: "", coverURL: nil,
                  remoteSource: .init(providerID: provider, itemID: "1"))
        } + [r.selection(3).track]
        defer { player.pause() }
        player.play(tracks, startAt: 0)
        try await waitFor { player.duration > 0 && !player.isLoading }
        for track in tracks.dropFirst() {
            player.next()
            try await waitFor { player.currentTrack == track && !player.isLoading }
            #expect(!player.isDiscovery)
        }
        player.pause()
        #expect(r.persistence.load()?.queue == tracks)
        #expect(r.persistence.load()?.currentIndex == 2)
    }

    @Test func testQualityReloadKeepsPlaybackIntentAndDoesNotReportPrefetch() async throws {
        let r = try rig(); defer { r.clean() }
        let resolver = StreamResolver()
        var requests: [String] = [], starts: [String] = []
        resolver.register("netease", stream: { id in
            requests.append(id)
            return .init(url: r.file, expiresAt: .distantFuture, isPreview: false)
        }, lyrics: { _ in .parse("") })
        let player = PlayerStore(resolver: resolver, persistence: r.persistence)
        func remote(_ id: String) -> Track {
            Track(discID: "7", number: id, title: id, artists: "", albumTitle: "", coverURL: nil,
                  remoteSource: .init(providerID: "netease", itemID: id))
        }
        var nextID = 1
        player.registerDiscovery("netease") { nextID += 1; return remote(String(nextID)) }
        player.reporting.onStart = { track, _ in starts.append(track.number) }
        player.playRemoteDiscovery(remote("1"), providerID: "netease")
        defer { player.pause() }
        try await waitFor { player.queuedNextTrack != nil && starts == ["1"] }
        #expect(starts == ["1"])
        player.pause(); player.seek(to: 5)
        player.remoteQualityDidChange(providerID: "netease")
        try await waitFor { requests.filter { $0 == "1" }.count == 2 && !player.isLoading }
        #expect(!player.isPlaying)
        #expect(abs(player.progress - 5) < 0.5)
        #expect(starts == ["1"])
        player.next()
        try await waitFor { requests.filter { $0 == "2" }.count == 2 }
        #expect(player.currentTrack?.number == "2")
        #expect(!player.isPlaying && starts == ["1"])
    }

    @Test func testLegacySnapshotStillDecodes() throws {
        let json = Data(#"{"queue":[],"currentIndex":0,"progress":0,"repeatMode":"off","isShuffled":false,"shuffledOrder":[]}"#.utf8)
        let value = try JSONDecoder().decode(PlaybackSnapshot.self, from: json)
        #expect(value.isDiscovery == nil)
    }
}

extension PlayerDiscoveryTests {
    @Test func disablingSourceCancelsPendingPlaybackWithoutWaitingForServer() async throws {
        let r = try rig(); defer { r.clean() }
        let resolver = StreamResolver()
        var resume: CheckedContinuation<Void, Never>?
        resolver.register("test-source", provider: PlaybackProvider(stream: { _ in
            await withCheckedContinuation { resume = $0 }
            return .init(url: r.file, expiresAt: .distantFuture, isPreview: false)
        }))
        let player = PlayerStore(resolver: resolver, persistence: r.persistence)
        let song = Track(discID: "7", number: "1", title: "", artists: "", albumTitle: "", coverURL: nil,
                         remoteSource: .init(providerID: "test-source", itemID: "1"))
        player.play([song], startAt: 0)
        try await waitFor { resume != nil }
        await player.disableProvider(providerID: "test-source")
        #expect(!player.isLoading && !player.isPlaying)
        let issue = player.issue
        resume?.resume()
        await Task.yield()
        #expect(player.issue == issue)
        #expect(!player.isPlaying)
    }
}

extension PlayerDiscoveryTests {
    @Test func registeredSelectionProviderSuppliesNextTrackWithoutDefaultPlatform() async throws {
        let r = try rig(); defer { r.clean() }
        let resolver = StreamResolver(localFile: { _ in r.file })
        resolver.register("dizzylab", provider: PlaybackProvider(stream: { _ in throw PlaybackError.unavailable }))
        let player = PlayerStore(resolver: resolver, persistence: r.persistence)
        var requests = 0
        player.registerDiscoverySelection("dizzylab") {
            requests += 1
            return r.selection(2)
        }
        player.playDiscovery(r.selection(1), autoplay: false)
        defer { player.play([r.selection(1).track], startAt: 0); player.pause() }
        try await waitFor { player.bufferedDiscoveryTrack?.number == "2" }
        #expect(requests == 1)
        player.next()
        try await waitFor { player.currentTrack?.number == "2" }
        #expect(player.issue == nil)
    }
}

extension PlayerDiscoveryTests {
    @Test(arguments: [false, true])
    func delayedDiscoveryStartCannotOverrideNewPlaybackIntent(changesProvider: Bool) async throws {
        let r = try rig(); defer { r.clean() }
        let original = r.selection(1).track
        r.player.play([original], startAt: 0)
        let intent = r.player.playbackIntentRevision
        let lateStart = Task {
            let next = try await r.source.fetch()
            try Task.checkCancellation()
            guard r.player.playbackIntentRevision == intent else { return false }
            r.player.playRemoteDiscovery(next.track, providerID: "qqmusic")
            return true
        }
        try await waitFor { r.source.pending != nil }
        let expected: Track
        if changesProvider {
            expected = Track(discID: "album", number: "9", title: "New selection", artists: "", albumTitle: "", coverURL: nil,
                             remoteSource: .init(providerID: "netease", itemID: "9"))
            r.player.play([expected], startAt: 0)
        } else {
            expected = original
            // Track and playing state return to their original values; only the
            // command revision records that this pending start was superseded.
            r.player.pause()
            r.player.resume()
        }
        #expect(r.player.playbackIntentRevision != intent)
        r.source.finish(r.selection(2))
        #expect(try await lateStart.value == false)
        #expect(r.player.currentTrack?.id == expected.id)
        #expect(r.player.isPlaying)
        #expect(!r.player.isDiscovery)
    }

    @Test func restoringProgressDoesNotSupersedePendingDiscoveryStart() async throws {
        let r = try rig(); defer { r.clean() }
        r.persistence.save(PlaybackSnapshot(queue: [r.selection(1).track], currentIndex: 0, progress: 5,
                                             repeatMode: .off, isShuffled: false, shuffledOrder: []))
        r.player.restore()
        r.player.resume()
        let intent = r.player.playbackIntentRevision
        let lateStart = Task {
            let next = try await r.source.fetch()
            try Task.checkCancellation()
            guard r.player.playbackIntentRevision == intent else { return false }
            r.player.playRemoteDiscovery(next.track, providerID: "qqmusic")
            return true
        }
        try await waitFor { r.source.pending != nil && r.player.duration > 0 && !r.player.isLoading && r.player.progress >= 5 }
        #expect(r.player.playbackIntentRevision == intent)
        r.source.finish(r.selection(2))
        #expect(try await lateStart.value)
        #expect(r.player.currentTrack?.number == "2")
        #expect(r.player.isDiscovery && r.player.isPlaying)
    }
}
