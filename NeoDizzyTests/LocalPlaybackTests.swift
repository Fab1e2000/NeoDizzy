import AVFoundation
import XCTest
@testable import NeoDizzy

@MainActor
final class LocalPlaybackTests: XCTestCase {
    func testLocalPlaybackQueueRestorationAndDirectoryAccessLifetime() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let suite = "LocalPlaybackTests.\(UUID())"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer {
            defaults.removePersistentDomain(forName: suite)
            try? FileManager.default.removeItem(at: root)
        }
        let url = root.appendingPathComponent("01 silence.wav")
        let format = try XCTUnwrap(AVAudioFormat(standardFormatWithSampleRate: 44100, channels: 1))
        let buffer = try XCTUnwrap(AVAudioPCMBuffer(pcmFormat: format, frameCapacity: 44100 * 5))
        buffer.frameLength = buffer.frameCapacity
        buffer.floatChannelData?[0].initialize(repeating: 0, count: Int(buffer.frameLength))
        do { let file = try AVAudioFile(forWriting: url, settings: format.settings); try file.write(from: buffer) }
        let scanner = LocalLibraryScanner(cacheURL: root.appendingPathComponent(".cache"))
        let library = OfflineLibraryStore(defaults: defaults, scanner: scanner)
        try await library.addScanFolder(root)
        let track = try XCTUnwrap(library.localAlbums.first?.tracks.first)
        weak var access = library.access(for: track)
        var networkCalls = 0
        let resolver = StreamResolver(fetch: { _ in networkCalls += 1; return [:] },
                                      localFile: { library.localFile(for: $0) }, localAccess: { library.access(for: $0) })
        let persistence = PlaybackPersistence(defaults: defaults)
        let player = PlayerStore(resolver: resolver, persistence: persistence)
        defer { player.pause() }
        player.play([track], startAt: 0)
        for _ in 0..<200 {
            if player.duration > 0 && player.progress > 0 { break }
            try await Task.sleep(for: .milliseconds(10))
        }
        XCTAssertGreaterThan(player.duration, 4)
        XCTAssertGreaterThan(player.progress, 0)
        XCTAssertNil(player.issue)
        XCTAssertFalse(player.isPreview)
        XCTAssertEqual(networkCalls, 0)
        player.pause()
        XCTAssertTrue(player.holdsFile(url), "Pausing does not release the audio file")
        XCTAssertThrowsError(try player.beginTagWrite(url))
        let savedProgress = player.progress
        player.stopForTagEditing(url)
        XCTAssertFalse(player.holdsFile(url))
        XCTAssertEqual(player.progress, savedProgress)
        try player.beginTagWrite(url)
        player.resume()
        XCTAssertFalse(player.isPlaying, "Remote resume must not reopen a file being edited")
        XCTAssertFalse(player.holdsFile(url))
        player.endTagWrite(url)
        let edited = Track(discID: track.discID, number: track.number, title: "新标题", artists: "新歌手",
                           albumTitle: track.albumTitle, coverURL: track.coverURL, duration: track.duration, localSource: track.localSource)
        player.refreshMetadata([edited])
        XCTAssertEqual(player.currentTrack?.id, track.id)
        XCTAssertEqual(player.currentTrack?.title, "新标题")
        XCTAssertEqual(player.progress, savedProgress)
        player.resume()
        for _ in 0..<100 {
            if player.duration > 0 && !player.isLoading { break }
            try await Task.sleep(for: .milliseconds(10))
        }
        player.pause()
        player.saveState()
        let restored = PlayerStore(resolver: resolver, persistence: persistence)
        restored.restore()
        XCTAssertEqual(restored.currentTrack?.id, track.id)
        XCTAssertEqual(restored.currentTrack?.localSource, track.localSource)
        XCTAssertFalse(restored.isPlaying)
        let source = try XCTUnwrap(library.scanFolders.first)
        await library.removeScanFolder(source.id)
        XCTAssertNotNil(access, "An active player must retain the directory's security scope")
        XCTAssertNil(library.localFile(for: track))
        XCTAssertEqual(networkCalls, 0)
    }
}
