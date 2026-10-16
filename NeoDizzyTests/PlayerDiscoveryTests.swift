import Foundation
import Testing
@testable import NeoDizzy

@Suite(.serialized) @MainActor struct PlayerDiscoveryTests {
    private final class Source {
        var calls = 0
        var pending: CheckedContinuation<ShuffleTrack, Error>?
        func fetch() async throws -> ShuffleTrack {
            calls += 1
            pending?.resume(throwing: CancellationError())
            return try await withCheckedThrowingContinuation { pending = $0 }
        }
        func finish(_ value: ShuffleTrack) { pending?.resume(returning: value); pending = nil }
        func fail() { pending?.resume(throwing: PlaybackError.unavailable); pending = nil }
    }
    private struct Rig {
        let player: PlayerStore
        let source: Source
        let persistence: PlaybackPersistence
        let defaults: UserDefaults
        let suite: String
        let file: URL
        func selection(_ number: Int) -> ShuffleTrack {
            ShuffleTrack(track: Track(discID: "test", number: String(number), title: "Track \(number)", artists: "", albumTitle: "Test", coverURL: nil), stream: file, label: "Test", tags: [])
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
        let resolver = StreamResolver(fetch: { _ in [:] }, localFile: { _ in file })
        return Rig(player: PlayerStore(resolver: resolver, persistence: persistence, fetchDiscovery: { try await source.fetch() }), source: source, persistence: persistence, defaults: defaults, suite: suite, file: file)
    }
    private func waitFor(_ condition: () -> Bool) async throws {
        for _ in 0..<200 {
            if condition() { return }
            try await Task.sleep(for: .milliseconds(10))
        }
        Issue.record("Timed out waiting for player state")
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
        try await waitFor { player.bufferedDiscoveryTrack?.number == "2" }
        #expect(requests == ["1", "2"])
        #expect(player.currentTrack?.number == "1")
        player.next()
        try await waitFor { player.currentTrack?.number == "2" }
        #expect(requests.filter { $0 == "2" }.count == 1)
        player.remoteAccountDidChange(providerID: "netease")
        #expect(player.bufferedDiscoveryTrack == nil)
    }

    @Test func testHeartModePersistsAndNormalPlaybackExitsIt() throws {
        let r = try rig(); defer { r.clean() }
        r.player.play([r.selection(1).track], startAt: 0, sourceID: 42, heartMode: true)
        r.player.pause()
        #expect(r.player.isHeartMode)
        #expect(r.persistence.load()?.sourceID == 42)
        #expect(r.persistence.load()?.heartMode == true)
        let restored = PlayerStore(persistence: r.persistence)
        restored.restore()
        #expect(restored.isHeartMode && !restored.isPlaying)
        restored.disableHeartMode()
        #expect(!restored.isHeartMode)
        r.player.play([r.selection(2).track], startAt: 0)
        #expect(!r.player.isHeartMode)
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
        try await waitFor { player.bufferedDiscoveryTrack != nil && starts == ["1"] }
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
