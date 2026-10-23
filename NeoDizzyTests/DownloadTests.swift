import Foundation
import Testing
@testable import NeoDizzy

struct DownloadTests {








    @Test(arguments: ["../escape", "/absolute", "nested/../../escape", "C:/Windows/file", "a\\..\\b", "a//b", "a/./b", "a\u{0000}b"])
    func rejectsUnsafePaths(_ path: String) {
        #expect(throws: DownloadFailure.self) { try SafeZipExtractor.validatePath(path) }
    }

    @Test func permitsUnicodeAndNormalDirectories() throws {
        #expect(try SafeZipExtractor.validatePath("专辑/01. 星光.mp3") == "专辑/01. 星光.mp3")
        #expect(try SafeZipExtractor.validatePath("专辑/") == "专辑")
    }

    @Test(arguments: [
        ("download-utf8.zip", "专辑/01. 星光.mp3"),
        ("download-gbk.zip", "01. 星光.mp3"),
        ("download-shiftjis.zip", "01. ｦ.mp3"),
    ])
    func extractsSupportedFilenameEncodings(_ fixture: String, _ filename: String) async throws {
        let root = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let zip = root.appendingPathComponent("input.zip")
        try Fixture.data(fixture).write(to: zip)
        let destination = root.appendingPathComponent("output")
        try await SafeZipExtractor.extract(zip, into: destination)
        #expect(try Data(contentsOf: destination.appendingPathComponent(filename)) == Data("test audio placeholder".utf8))
    }

    @Test(arguments: ["download-traversal.zip", "download-symlink.zip", "download-bad-crc.zip"])
    func rejectsDangerousOrDamagedArchivesAndRemovesPartialOutput(_ fixture: String) async throws {
        let root = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let zip = root.appendingPathComponent("input.zip")
        try Fixture.data(fixture).write(to: zip)
        let destination = root.appendingPathComponent("output")
        await #expect(throws: DownloadFailure.self) { try await SafeZipExtractor.extract(zip, into: destination) }
        #expect(!FileManager.default.fileExists(atPath: destination.path))
        #expect(!FileManager.default.fileExists(atPath: root.appendingPathComponent("escape.mp3").path))
    }

    @Test func rejectsHTMLResponseAndSizeLimitBeforeImport() async throws {
        let root = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let zip = root.appendingPathComponent("input.zip")
        try Data("<!doctype html><title>Login</title>".utf8).write(to: zip)
        #expect(throws: DownloadFailure.self) { try SafeZipExtractor.validateZIP(zip) }
        try Fixture.data("download-utf8.zip").write(to: zip)
        var limits = SafeZipExtractor.Limits()
        limits.totalBytes = 1
        await #expect(throws: DownloadFailure.self) {
            try await SafeZipExtractor.extract(zip, into: root.appendingPathComponent("output"), limits: limits)
        }
    }

    @Test func cancellationDoesNotLeaveAnExtractedLibrary() async throws {
        let root = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let zip = root.appendingPathComponent("input.zip")
        try Fixture.data("download-utf8.zip").write(to: zip)
        let destination = root.appendingPathComponent("output")
        let task = Task {
            while !Task.isCancelled { await Task.yield() }
            try await SafeZipExtractor.extract(zip, into: destination)
        }
        task.cancel()
        await #expect(throws: CancellationError.self) { try await task.value }
        #expect(!FileManager.default.fileExists(atPath: destination.path))
    }









    @Test func resolvesAmbiguousJapaneseEncodingWithPublishedTrackTitle() async throws {
        let root = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let zip = root.appendingPathComponent("input.zip")
        try Fixture.data("download-shiftjis-ambiguous.zip").write(to: zip)
        let destination = root.appendingPathComponent("output")
        let track = Track(discID: "TEST", number: "1", title: "夜空", artists: "", albumTitle: "", coverURL: nil)
        try await SafeZipExtractor.extract(zip, into: destination, expectedTracks: [track])
        #expect(FileManager.default.fileExists(atPath: destination.appendingPathComponent("夜空.flac").path))
        await #expect(throws: DownloadFailure.self) {
            try await SafeZipExtractor.extract(zip, into: root.appendingPathComponent("ambiguous"))
        }
    }

    private func temporaryDirectory() throws -> URL {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        return root
    }
}

/// Delivers headers only. Successful resolution proves that no body or end-of-stream is required.


@MainActor
struct DownloadBackgroundBridgeTests {
    @Test func completesExactlyOnceInEitherCallbackOrder() {
        var count = 0
        BackgroundDownloadBridge.handleEvents(identifier: BackgroundDownloadBridge.identifier) { count += 1 }
        #expect(count == 0)
        BackgroundDownloadBridge.finishEvents()
        #expect(count == 1)

        BackgroundDownloadBridge.finishEvents()
        #expect(count == 1)
        BackgroundDownloadBridge.handleEvents(identifier: BackgroundDownloadBridge.identifier) { count += 1 }
        #expect(count == 2)

        BackgroundDownloadBridge.handleEvents(identifier: "other.session") { count += 1 }
        #expect(count == 3)
        BackgroundDownloadBridge.handleEvents(identifier: BackgroundDownloadBridge.identifier) { count += 1 }
        BackgroundDownloadBridge.finishEvents()
        #expect(count == 4)
    }
}



struct DownloadProgressThrottleTests {
    @Test func fastTransferHasBoundedUpdatesAndImmediateCompletion() {
        var throttle = DownloadProgressThrottle()
        let id = UUID()
        let start = ContinuousClock.now
        var emissions = 0
        for tick in 0..<10_000 {
            if throttle.shouldEmit(id: id, written: Int64(tick), expected: 10_000,
                                   now: start.advanced(by: .milliseconds(tick))) {
                emissions += 1
            }
        }
        #expect(emissions == 40)
        let emitted1 = throttle.shouldEmit(id: id, written: 10_000, expected: 10_000,
                                   now: start.advanced(by: .milliseconds(9_999)))
        #expect(emitted1)
        let emitted2 = !throttle.shouldEmit(id: id, written: 10_000, expected: 10_000,
                                    now: start.advanced(by: .seconds(11)))
        #expect(emitted2)
    }

    @Test func concurrentTransfersAndUnknownSizesDoNotFloodUI() {
        var throttle = DownloadProgressThrottle()
        let first = UUID(), second = UUID()
        let start = ContinuousClock.now
        let emitted3 = throttle.shouldEmit(id: first, written: 1, expected: -1, now: start)
        #expect(emitted3)
        let emitted4 = throttle.shouldEmit(id: first, written: 2, expected: -1, now: start.advanced(by: .milliseconds(250)))
        #expect(emitted4)
        let emitted5 = throttle.shouldEmit(id: second, written: 1, expected: 100, now: start)
        #expect(emitted5)
        let emitted6 = !throttle.shouldEmit(id: second, written: 2, expected: 100, now: start.advanced(by: .milliseconds(20)))
        #expect(emitted6)
        let emitted7 = throttle.shouldEmit(id: first, written: 3, expected: 100, now: start.advanced(by: .milliseconds(20)))
        #expect(emitted7)
        throttle.finish(second)
        let emitted8 = throttle.shouldEmit(id: second, written: 1, expected: 100, now: start.advanced(by: .milliseconds(30)))
        #expect(emitted8)
    }
}
