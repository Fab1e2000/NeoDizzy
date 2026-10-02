import Foundation
import AVFoundation
import Testing
@testable import NeoDizzy

@Suite struct AudioTagEditingTests {
    private func temporary() throws -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    @Test(arguments: ["flac", "mp3", "m4a", "wav", "aiff"])
    func editsEmbeddedTagsWithoutChangingDecodedAudio(format: String) async throws {
        let root = try temporary()
        defer { try? FileManager.default.removeItem(at: root) }
        let url = root.appendingPathComponent("song.\(format)")
        if ["wav", "aiff"].contains(format) {
            let pcm = try #require(AVAudioFormat(standardFormatWithSampleRate: 44100, channels: 1))
            let buffer = try #require(AVAudioPCMBuffer(pcmFormat: pcm, frameCapacity: 4410))
            buffer.frameLength = 4410
            buffer.floatChannelData?[0].initialize(repeating: 0, count: 4410)
            let file = try AVAudioFile(forWriting: url, settings: pcm.settings)
            try file.write(from: buffer)
        } else { try Fixture.data("audio-local-tags.\(format)").write(to: url) }
        let before = try decoded(url)
        let lyricsBefore = try await LocalLyricsReader(directory: root.appendingPathComponent("lyrics")).load(trackID: "song", audioURL: url, access: OfflineFolderAccess(url: root))
        let service = AudioTagEditor()
        let access = OfflineFolderAccess(url: root)
        let initial = try await service.read(url, access: access)
        var edited = initial.document
        edited.setText("TITLE", "新的标题")
        edited.values["ARTIST"] = ["歌手甲", "AC/DC"]
        edited.values["ALBUMARTIST"] = ["作者甲", "作者乙"]
        edited.setText("ALBUM", "新的专辑")
        edited.setText("TRACKNUMBER", "4/12")
        edited.setText("DISCNUMBER", "2/3")
        edited.setText("DATE", "2026")
        edited.setText("GENRE", "电子")
        // Same synthetic PNG across all containers, including WAV and AIFF.
        let tagged = root.appendingPathComponent("cover-source.flac")
        try Fixture.data("audio-local-tags.flac").write(to: tagged)
        edited.cover = try AudioTagCodec.read(tagged).cover
        try await service.save(edited, snapshot: initial, url: url, access: access)
        let saved = try await service.read(url, access: access)
        #expect(saved.document == edited)
        if let directory = ProcessInfo.processInfo.environment["NEODIZZY_TAG_VALIDATION_DIR"] {
            let output = URL(fileURLWithPath: directory, isDirectory: true)
            try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)
            let exported = output.appendingPathComponent("edited.\(format)")
            // The caller provides a new, dedicated validation directory.
            try FileManager.default.copyItem(at: url, to: exported)
        }
        #expect(try decoded(url) == before)
        let lyricsAfter = try await LocalLyricsReader(directory: root.appendingPathComponent("lyrics")).load(trackID: "song", audioURL: url, access: access)
        #expect(lyricsAfter.lines == lyricsBefore.lines)
        var cleared = saved.document
        for key in AudioTagDocument.keys { cleared.values[key] = [] }
        cleared.cover = ""
        try await service.save(cleared, snapshot: saved, url: url, access: access)
        #expect(try AudioTagCodec.read(url) == cleared)
        #expect(try decoded(url) == before)
    }

    @Test func conflictsCancellationAndInvalidInputLeaveOriginalIntact() async throws {
        let root = try temporary()
        defer { try? FileManager.default.removeItem(at: root) }
        let url = root.appendingPathComponent("song.flac")
        try Fixture.data("audio-local-tags.flac").write(to: url)
        let service = AudioTagEditor()
        let access = OfflineFolderAccess(url: root)
        let snapshot = try await service.read(url, access: access)
        var draft = snapshot.document
        draft.setText("TITLE", "edited")
        var external = snapshot.document
        external.setText("TITLE", "external change")
        try AudioTagCodec.write(external, original: snapshot.document, to: url)
        let original = try Data(contentsOf: url)
        await #expect(throws: (any Error).self) { try await service.save(draft, snapshot: snapshot, url: url, access: access) }
        #expect(try Data(contentsOf: url) == original)
        let fresh = try await service.read(url, access: access)
        draft.setText("TRACKNUMBER", "-1")
        await #expect(throws: (any Error).self) { try await service.save(draft, snapshot: fresh, url: url, access: access) }
        #expect(try Data(contentsOf: url) == original)
        let task = Task {
            try Task.checkCancellation()
            try await service.save(external, snapshot: fresh, url: url, access: access)
        }
        task.cancel()
        _ = await task.result
        #expect(try Data(contentsOf: url) == original)
        let link = root.appendingPathComponent("link.flac")
        try FileManager.default.createSymbolicLink(at: link, withDestinationURL: url)
        await #expect(throws: (any Error).self) { try await service.read(link, access: access) }
    }

    @Test(arguments: ["flac", "mp3", "m4a"])
    func preservesCustomTagsAndSecondaryPictures(format: String) async throws {
        let root = try temporary()
        defer { try? FileManager.default.removeItem(at: root) }
        let url = root.appendingPathComponent("preserved.\(format)")
        try Fixture.data("audio-tag-preservation.\(format)").write(to: url)
        let beforeAudio = try decoded(url)
        let editor = AudioTagEditor()
        let access = OfflineFolderAccess(url: root)
        let snapshot = try await editor.read(url, access: access)
        var draft = snapshot.document
        draft.setText("TITLE", "保留附加标签")
        draft.cover = try Fixture.data("tag-cover-replacement.png").base64EncodedString()
        try await editor.save(draft, snapshot: snapshot, url: url, access: access)
        #expect(try AudioTagCodec.read(url).cover == draft.cover)
        #expect(try decoded(url) == beforeAudio)
        if let directory = ProcessInfo.processInfo.environment["NEODIZZY_TAG_VALIDATION_DIR"] {
            let output = URL(fileURLWithPath: directory, isDirectory: true)
            try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)
            try FileManager.default.copyItem(at: url, to: output.appendingPathComponent("preserved.\(format)"))
        }
    }

    @Test func validationPreservesUntouchedLegacyValues() throws {
        let original = AudioTagDocument(values: ["TITLE": ["  原标题  "], "TRACKNUMBER": ["unknown"], "DATE": ["2020-01-02"]], cover: "")
        var draft = original
        draft.values["ARTIST"] = ["  AC/DC  ", ""]
        let validated = try draft.validated(preserving: original)
        #expect(validated.values["TITLE"] == original.values["TITLE"])
        #expect(validated.values["TRACKNUMBER"] == original.values["TRACKNUMBER"])
        #expect(validated.values["DATE"] == original.values["DATE"])
        #expect(validated.values["ARTIST"] == ["AC/DC"])
    }

    @Test func batchPatchOnlyChangesExplicitFields() throws {
        let original = AudioTagDocument(values: ["TITLE": ["独立歌名"], "ARTIST": ["原歌手"], "ALBUM": ["原专辑"], "TRACKNUMBER": ["7"], "DISCNUMBER": ["2"], "GENRE": ["Rock"]], cover: "original")
        var patch = AudioTagBatchPatch()
        patch.fields = ["ARTIST", "ALBUM", "GENRE"]
        patch.values.values["ARTIST"] = ["歌手甲", "AC/DC"]
        patch.values.setText("ALBUM", "统一专辑")
        let updated = try patch.applying(to: original)
        #expect(updated.values["ARTIST"] == ["歌手甲", "AC/DC"])
        #expect(updated.text("ALBUM") == "统一专辑")
        #expect(updated.values["GENRE"] == [])
        #expect(updated.text("TITLE") == "独立歌名")
        #expect(updated.text("TRACKNUMBER") == "7")
        #expect(updated.text("DISCNUMBER") == "2")
        #expect(updated.cover == "original")
        patch.replacesCover = true
        #expect(try patch.applying(to: original).cover.isEmpty)
    }

    @Test func batchFLACEditsAndContentTypeValidation() async throws {
        let root = try temporary()
        defer { try? FileManager.default.removeItem(at: root) }
        let editor = AudioTagEditor()
        let access = OfflineFolderAccess(url: root)
        var patch = AudioTagBatchPatch()
        patch.fields = ["ALBUMARTIST", "DATE"]
        patch.values.values["ALBUMARTIST"] = ["作者甲", "作者乙"]
        patch.values.setText("DATE", "2026")
        for number in 1...2 {
            let url = root.appendingPathComponent("track-\(number).flac")
            try Fixture.data("audio-local-tags.flac").write(to: url)
            let initial = try await editor.read(url, access: access, flacOnly: true)
            let audio = try decoded(url)
            try await editor.save(patch.applying(to: initial.document), snapshot: initial, url: url, access: access)
            let result = try AudioTagCodec.read(url)
            #expect(result.values["ALBUMARTIST"] == ["作者甲", "作者乙"])
            #expect(result.text("TITLE") == initial.document.text("TITLE"))
            #expect(result.cover == initial.document.cover)
            #expect(try decoded(url) == audio)
        }
        let disguised = root.appendingPathComponent("not-flac.flac")
        let original = try Fixture.data("audio-local-tags.mp3")
        try original.write(to: disguised)
        await #expect(throws: (any Error).self) { try await editor.read(disguised, access: access, flacOnly: true) }
        #expect(try Data(contentsOf: disguised) == original)
    }

    private func decoded(_ url: URL) throws -> Data {
        let file = try AVAudioFile(forReading: url)
        let buffer = try #require(AVAudioPCMBuffer(pcmFormat: file.processingFormat, frameCapacity: AVAudioFrameCount(file.length)))
        try file.read(into: buffer)
        var result = Data()
        let buffers = UnsafeMutableAudioBufferListPointer(buffer.mutableAudioBufferList)
        for audio in buffers { if let data = audio.mData { result.append(Data(bytes: data, count: Int(audio.mDataByteSize))) } }
        return result
    }
}
