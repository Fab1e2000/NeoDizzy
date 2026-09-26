import XCTest
@testable import NeoDizzy

@MainActor final class PlayerDiscoveryTests: XCTestCase {
    private final class Source {
        var calls = 0
        var pending: CheckedContinuation<ShuffleTrack, Error>?
        func fetch() async throws -> ShuffleTrack {
            calls += 1
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
        func clean() { player.pause(); defaults.removePersistentDomain(forName: suite); try? FileManager.default.removeItem(at: file) }
    }
    private func rig() throws -> Rig {
        let suite = "PlayerDiscoveryTests.\(UUID())"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
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
        XCTFail("Timed out waiting for player state")
    }
    func testNextRequestsNewTrackPreviousReturnsHistoryBeyondThreeSeconds() async throws {
        let r = try rig(); defer { r.clean() }
        r.player.playDiscovery(r.selection(1), autoplay: false)
        XCTAssertFalse(r.player.canPlayPrevious)
        XCTAssertTrue(r.player.canPlayNext)
        r.player.next(); r.player.next()
        try await waitFor { r.source.calls == 1 }
        XCTAssertFalse(r.player.canPlayNext)
        r.source.finish(r.selection(2))
        try await waitFor { r.player.currentTrack?.number == "2" }
        XCTAssertFalse(r.player.isPlaying)
        r.player.seek(to: 10)
        r.player.previous()
        XCTAssertEqual(r.player.currentTrack?.number, "1")
        XCTAssertEqual(r.player.progress, 0)
        r.player.next()
        try await waitFor { r.source.calls == 2 }
        r.source.finish(r.selection(3))
        try await waitFor { r.player.currentTrack?.number == "3" }
        r.player.previous()
        XCTAssertEqual(r.player.currentTrack?.number, "1")
    }
    func testOrdinaryAlbumRejectsLateDiscoveryResponse() async throws {
        let r = try rig(); defer { r.clean() }
        r.player.playDiscovery(r.selection(1), autoplay: false)
        r.player.next()
        try await waitFor { r.source.pending != nil }
        r.player.play([r.selection(8).track, r.selection(9).track], startAt: 0)
        r.player.pause()
        r.source.finish(r.selection(2))
        try await Task.sleep(for: .milliseconds(100))
        XCTAssertEqual(r.player.currentTrack?.number, "8")
        XCTAssertFalse(r.player.isDiscovery)
        r.player.next()
        XCTAssertEqual(r.player.currentTrack?.number, "9")
        XCTAssertEqual(r.source.calls, 1)
    }
    func testPreviousCancelsPendingNext() async throws {
        let r = try rig(); defer { r.clean() }
        r.player.playDiscovery(r.selection(1), autoplay: false)
        r.player.next(); try await waitFor { r.source.pending != nil }
        r.source.finish(r.selection(2)); try await waitFor { r.player.currentTrack?.number == "2" }
        r.player.next(); try await waitFor { r.source.pending != nil }
        r.player.previous()
        r.source.finish(r.selection(3))
        try await Task.sleep(for: .milliseconds(100))
        XCTAssertEqual(r.player.currentTrack?.number, "1")
        XCTAssertTrue(r.player.canPlayNext)
    }
    func testFailurePreservesHistoryAndCanRetry() async throws {
        let r = try rig(); defer { r.clean() }
        r.player.playDiscovery(r.selection(1), autoplay: false)
        r.player.next(); try await waitFor { r.source.pending != nil }
        r.source.fail(); try await waitFor { r.player.canPlayNext }
        XCTAssertEqual(r.player.currentTrack?.number, "1")
        XCTAssertTrue(r.player.issue?.contains("获取下一首失败") == true)
        r.player.next(); try await waitFor { r.source.calls == 2 }
        r.source.finish(r.selection(2)); try await waitFor { r.player.currentTrack?.number == "2" }
        XCTAssertNil(r.player.issue)
    }
    func testPauseDuringRequestAndRestoreDiscoveryMode() async throws {
        let r = try rig(); defer { r.clean() }
        r.player.playDiscovery(r.selection(1))
        r.player.next(); try await waitFor { r.source.pending != nil }
        r.player.pause()
        r.source.finish(r.selection(2)); try await waitFor { r.player.currentTrack?.number == "2" }
        XCTAssertFalse(r.player.isPlaying)
        r.player.saveState()
        let restored = PlayerStore(persistence: r.persistence)
        restored.restore()
        XCTAssertTrue(restored.isDiscovery && restored.canPlayPrevious && restored.canPlayNext)
        XCTAssertEqual(restored.currentTrack?.number, "2")
        XCTAssertFalse(restored.isPlaying)
    }
    func testLegacySnapshotStillDecodes() throws {
        let json = Data(#"{"queue":[],"currentIndex":0,"progress":0,"repeatMode":"off","isShuffled":false,"shuffledOrder":[]}"#.utf8)
        let value = try JSONDecoder().decode(PlaybackSnapshot.self, from: json)
        XCTAssertNil(value.isDiscovery)
    }
}
