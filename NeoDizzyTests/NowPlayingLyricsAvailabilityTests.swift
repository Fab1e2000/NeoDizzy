import Foundation
import Testing
@testable import NeoDizzy

@MainActor struct NowPlayingLyricsAvailabilityTests {
    @Test(arguments: ["", " \n", "[00:01.00]", "[ar:Artist]"])
    func emptyLyricsHaveNoEntry(text: String) async {
        let model = NowPlayingLyricsModel()
        await model.load(trackID: "a") { LocalLyrics.parse(text) }
        #expect(model.availability(for: "a") == .unavailable)
    }

    @Test(arguments: ["Plain lyrics", "[00:01.00]Timed lyrics"])
    func entryRequiresCurrentTrackLyrics(text: String) async {
        let model = NowPlayingLyricsModel()
        #expect(model.availability(for: "a") == .loading)
        await model.load(trackID: "a") {
            #expect(model.availability(for: "a") == .loading)
            return LocalLyrics.parse(text)
        }
        #expect(model.availability(for: "a") == .available)
        #expect(model.availability(for: "b") == .loading)
    }

    @Test(arguments: ["a", "b"])
    func obsoleteSuccessCannotRestoreEntry(newTrackID: String) async {
        let model = NowPlayingLyricsModel()
        await model.load(trackID: "a") {
            await model.load(trackID: newTrackID) { LocalLyrics.parse("") }
            return LocalLyrics.parse("Obsolete lyrics")
        }
        #expect(model.availability(for: newTrackID) == .unavailable)
        #expect(model.lyrics?.isEmpty == true)
    }

    @Test func obsoleteErrorCannotHideNewLyrics() async {
        let model = NowPlayingLyricsModel()
        await model.load(trackID: "a") {
            await model.load(trackID: "b") { LocalLyrics.parse("Current lyrics") }
            throw LocalLyricsError.invalidFile
        }
        #expect(model.availability(for: "b") == .available)
        #expect(model.error == nil)
    }

    @Test func failureRemovesPreviousLyricsEntry() async {
        let model = NowPlayingLyricsModel()
        await model.load(trackID: "a") { LocalLyrics.parse("Previous lyrics") }
        await model.load(trackID: "a") { throw LocalLyricsError.invalidFile }
        #expect(model.availability(for: "a") == .unavailable)
        #expect(model.lyrics == nil)
        #expect(model.error != nil)
    }

    @Test func importingLyricsTriggersReloadAndRestoresEntry() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let reader = LocalLyricsReader(directory: directory.appendingPathComponent("saved"))
        let model = NowPlayingLyricsModel(reader: reader)
        await model.load(trackID: "a") { LocalLyrics.parse("") }
        let file = directory.appendingPathComponent("lyrics.lrc")
        try "[00:01.00]Imported lyrics".write(to: file, atomically: true, encoding: .utf8)
        await model.importFile(file, trackID: "a")
        #expect(model.revision == 1)
        await model.load(trackID: "a") {
            try await reader.load(trackID: "a", audioURL: nil, access: nil)
        }
        #expect(model.availability(for: "a") == .available)
        #expect(model.lyrics?.source == "已导入歌词")
        await model.importFile(file, trackID: "b")
        #expect(model.revision == 1)
    }
}
