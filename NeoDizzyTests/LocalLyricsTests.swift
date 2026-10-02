import Foundation
import Testing
@testable import NeoDizzy

struct LocalLyricsTests {
    @Test func timestampsOffsetsTranslationsAndSeeking() {
        let lyrics = LocalLyrics.parse("\u{FEFF}[ar:artist]\n[offset:-500]\n[00:01.00][00:04.000]first\n[00:01.00]translation\n[00:03.5]second")
        #expect(lyrics.lines.map(\.time) == [0.5, 3, 3.5])
        #expect(lyrics.lines[0].text == "first\ntranslation")
        #expect(lyrics.activeLine(at: 0.4) == nil)
        #expect(lyrics.activeLine(at: 0.5) == 0)
        #expect(lyrics.activeLine(at: 3.2) == 1)
        #expect(lyrics.activeLine(at: 30) == 2)
        #expect(lyrics.activeLine(at: 1) == 0)
        #expect(LocalLyrics.parse("普通歌词\n第二行").plainText == "普通歌词\n第二行")
        #expect(LocalLyrics.parse("[ar:name]\n[offset:50]").isEmpty)
    }

    @Test(arguments: ["mp3", "flac", "m4a"])
    func embeddedLyricsUseSystemMetadata(_ ext: String) async throws {
        let cache = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: cache, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: cache) }
        let url = cache.appendingPathComponent("audio.\(ext)")
        try Fixture.data("audio-local-tags.\(ext)").write(to: url)
        let result = try await LocalLyricsReader(directory: cache).load(trackID: "local/test", audioURL: url,
            access: OfflineFolderAccess(url: url.deletingLastPathComponent()))
        #expect(result.source == "内嵌歌词")
        #expect(result.lines.map(\.text) == ["测试歌词", "第二行"])
    }

    @Test func sidecarAndImportedLyricsTakePriorityAndStayTrackScoped() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let audio = root.appendingPathComponent("song.flac")
        try Fixture.data("audio-local-tags.flac").write(to: audio)
        let sidecar = root.appendingPathComponent("song.lrc")
        try Data("[00:01]sidecar".utf8).write(to: sidecar)
        let imported = root.appendingPathComponent("import.txt")
        try "Imported plain lyrics".data(using: .utf16)!.write(to: imported)
        let reader = LocalLyricsReader(directory: root.appendingPathComponent("cache"))
        let access = OfflineFolderAccess(url: root)
        let local = try await reader.load(trackID: "one", audioURL: audio, access: access)
        #expect(local.source == "同目录 LRC")
        #expect(local.lines.first?.text == "sidecar")
        try await reader.importFile(imported, trackID: "one")
        let saved = try await reader.load(trackID: "one", audioURL: nil, access: nil)
        #expect(saved.plainText == "Imported plain lyrics")
        #expect(saved.source == "已导入歌词")
        let absent = try await reader.load(trackID: "other", audioURL: nil, access: nil)
        #expect(absent.isEmpty)
        #expect(try String(contentsOf: sidecar, encoding: .utf8) == "[00:01]sidecar")
        try Data(repeating: 65, count: 1_048_577).write(to: imported)
        await #expect(throws: LocalLyricsError.self) { try await reader.importFile(imported, trackID: "one") }
        let unchanged = try await reader.load(trackID: "one", audioURL: nil, access: nil)
        #expect(unchanged == saved)
    }

    @Test func symlinkSidecarCannotEscapeAuthorizedFolder() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let audio = root.appendingPathComponent("song.flac")
        try Fixture.data("audio-local-tags.flac").write(to: audio)
        let outside = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".lrc")
        defer { try? FileManager.default.removeItem(at: outside) }
        try Data("[00:00]outside".utf8).write(to: outside)
        try FileManager.default.createSymbolicLink(at: root.appendingPathComponent("song.lrc"), withDestinationURL: outside)
        let result = try await LocalLyricsReader(directory: root.appendingPathComponent("cache"))
            .load(trackID: "song", audioURL: audio, access: OfflineFolderAccess(url: root))
        #expect(result.source == "内嵌歌词")
        #expect(result.lines.first?.text == "测试歌词")
    }
}
