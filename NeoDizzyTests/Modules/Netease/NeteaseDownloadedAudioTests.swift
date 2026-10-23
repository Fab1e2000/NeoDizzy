import Foundation
import Testing
@testable import NeoDizzy

@MainActor struct NeteaseDownloadedAudioTests {
    private func directory() throws -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    @Test(arguments: ["flac", "mp3", "long"])
    func restoresOriginalBytesAndActualExtension(_ kind: String) async throws {
        let root = try directory()
        defer { try? FileManager.default.removeItem(at: root) }
        let source = root.appendingPathComponent("download.archive")
        let encrypted = try Fixture.data("audio-ncm-\(kind).ncm")
        try encrypted.write(to: source)
        // The API may claim FLAC even when the container actually holds MP3.
        let output = try await NeteaseDownloadedAudio.prepare(source, declaredType: "flac", staging: root)
        let format = kind == "mp3" ? "mp3" : "flac"
        var expected = try Fixture.data("audio-local-tags.\(format)")
        if kind == "long" { expected.append(contentsOf: (0..<150_003).map { UInt8($0 % 251) }) }
        #expect(output.pathExtension == format)
        #expect(try Data(contentsOf: output) == expected)
        #expect(try Data(contentsOf: source) == encrypted)
        if kind != "long" { _ = try AudioTagCodec.read(output) }
    }

    @Test func preservesOrdinaryAudio() async throws {
        let root = try directory()
        defer { try? FileManager.default.removeItem(at: root) }
        let source = root.appendingPathComponent("source")
        let bytes = try Fixture.data("audio-local-tags.flac")
        try bytes.write(to: source)
        let output = try await NeteaseDownloadedAudio.prepare(source, declaredType: "flac", staging: root)
        #expect(try Data(contentsOf: output) == bytes)
    }

    @Test(arguments: [0, 8, 12, 30, 64, 90])
    func rejectsTruncatedContainer(_ count: Int) async throws {
        let root = try directory()
        defer { try? FileManager.default.removeItem(at: root) }
        let source = root.appendingPathComponent("source")
        try Fixture.data("audio-ncm-flac.ncm").prefix(count).write(to: source)
        await #expect(throws: NeteaseDownloadedAudio.Failure.self) {
            try await NeteaseDownloadedAudio.prepare(source, declaredType: "ncm", staging: root)
        }
        #expect(try FileManager.default.contentsOfDirectory(atPath: root.path) == ["source"])
    }

    @Test func rejectsBadKeyLengthAndUnsupportedPayloadWithoutLeavingOutput() async throws {
        let root = try directory()
        defer { try? FileManager.default.removeItem(at: root) }
        let source = root.appendingPathComponent("source")
        let original = try Fixture.data("audio-ncm-flac.ncm")
        for offset in [10, 14, 114] { // key length, encrypted key, first payload byte
            var damaged = original
            damaged[offset] ^= 0xff
            try damaged.write(to: source)
            await #expect(throws: NeteaseDownloadedAudio.Failure.self) {
                try await NeteaseDownloadedAudio.prepare(source, declaredType: "ncm", staging: root)
            }
            #expect(try FileManager.default.contentsOfDirectory(atPath: root.path) == ["source"])
        }
    }

    @Test(arguments: ["mp3", "flac"])
    func rejectsErrorResponseDisguisedAsAudio(_ format: String) async throws {
        let root = try directory()
        defer { try? FileManager.default.removeItem(at: root) }
        let source = root.appendingPathComponent("source")
        let bytes = Data("invalid audio".utf8)
        try bytes.write(to: source)
        await #expect(throws: NeteaseDownloadedAudio.Failure.self) {
            try await NeteaseDownloadedAudio.prepare(source, declaredType: format, staging: root)
        }
        #expect(try Data(contentsOf: source) == bytes)
        #expect(try FileManager.default.contentsOfDirectory(atPath: root.path) == ["source"])
    }

    @Test func respectsCancellation() async throws {
        let root = try directory()
        defer { try? FileManager.default.removeItem(at: root) }
        let task = Task {
            withUnsafeCurrentTask { $0?.cancel() }
            return try await NeteaseDownloadedAudio.prepare(root.appendingPathComponent("missing"), declaredType: "ncm", staging: root)
        }
        await #expect(throws: CancellationError.self) { try await task.value }
        #expect(try FileManager.default.contentsOfDirectory(atPath: root.path).isEmpty)
    }
}
