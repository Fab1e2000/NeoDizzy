import Foundation
import Testing
@testable import NeoDizzy

struct LibraryCollectionUpdateTests {
    @Test(arguments: ["mp3", "flac"])
    func qualityReplacementUpdatesAudioAndManifestWithoutLosingOtherFiles(_ suffix: String) throws {
        let fixture = try CollectionUpdateFixture()
        defer { fixture.remove() }
        try fixture.installInitial()
        try Data("private notes".utf8).write(to: fixture.target.appendingPathComponent(".notes"))
        try FileManager.default.createDirectory(at: fixture.target.appendingPathComponent(".extras"), withIntermediateDirectories: true)
        try Data("sidecar".utf8).write(to: fixture.target.appendingPathComponent(".extras/info.txt"))
        let oldB = try Data(contentsOf: fixture.target.appendingPathComponent("b.mp3"))
        let incoming = try fixture.stage([("a", "a.\(suffix)", "new quality")], quality: suffix == "mp3" ? "mp3_320" : "flac")
        let result = try #require(try fixture.commit(incoming, updating: true))
        #expect(result.manifest.entries.map(\.itemID) == ["a", "b"])
        #expect(result.manifest.entries.first?.quality == (suffix == "mp3" ? "mp3_320" : "flac"))
        #expect(result.manifest.title == "Original collection")
        #expect(result.manifest.extra == .object(["keep": .string("metadata")]))
        #expect(try Data(contentsOf: fixture.target.appendingPathComponent("a.\(suffix)")) == Data("new quality".utf8))
        #expect(try Data(contentsOf: fixture.target.appendingPathComponent("b.mp3")) == oldB)
        #expect(try Data(contentsOf: fixture.target.appendingPathComponent(".notes")) == Data("private notes".utf8))
        #expect(try Data(contentsOf: fixture.target.appendingPathComponent(".extras/info.txt")) == Data("sidecar".utf8))
        if suffix != "mp3" { #expect(!FileManager.default.fileExists(atPath: fixture.target.appendingPathComponent("a.mp3").path)) }
    }

    @Test func updateCanCreateAndAppendWithoutReorderingExistingSongs() throws {
        let fixture = try CollectionUpdateFixture()
        defer { fixture.remove() }
        let first = try fixture.stage([("a", "a.mp3", "first")])
        _ = try fixture.commit(first, updating: true)
        let next = try fixture.stage([("b", "b.flac", "second")], quality: "flac")
        let result = try #require(try fixture.commit(next, updating: true))
        #expect(result.manifest.entries.map(\.itemID) == ["a", "b"])
        #expect(try Data(contentsOf: fixture.target.appendingPathComponent("a.mp3")) == Data("first".utf8))
    }

    @Test func failureLeavesExistingAudioAndManifestByteForByteIntact() throws {
        let fixture = try CollectionUpdateFixture()
        defer { fixture.remove() }
        try fixture.installInitial()
        let before = try fixture.snapshot()
        // A changed filename cannot overwrite another song or an unrelated sidecar.
        let collision = try fixture.stage([("a", "b.mp3", "must not replace b")])
        #expect(throws: OfflineLibraryError.self) { try fixture.commit(collision, updating: true) }
        #expect(try fixture.snapshot() == before)
        let foreign = try fixture.stage([("a", "a.flac", "wrong collection")], sourceID: "other")
        #expect(throws: OfflineLibraryError.self) { try fixture.commit(foreign, updating: true) }
        #expect(try fixture.snapshot() == before)
        let missing = try fixture.stage([("a", "a.flac", "missing audio")])
        try FileManager.default.removeItem(at: fixture.staging.appendingPathComponent("a.flac"))
        #expect(throws: OfflineLibraryError.self) { try fixture.commit(missing, updating: true) }
        #expect(try fixture.snapshot() == before)
    }

    @Test func existingMergeBehaviorDoesNotReplaceAudio() throws {
        let fixture = try CollectionUpdateFixture()
        defer { fixture.remove() }
        try fixture.installInitial()
        let before = try Data(contentsOf: fixture.target.appendingPathComponent("a.mp3"))
        let incoming = try fixture.stage([("a", "a.flac", "new audio")], quality: "flac")
        let result = try #require(try fixture.commit(incoming, updating: false))
        #expect(result.manifest.entries.first?.relativePath == "a.mp3")
        #expect(try Data(contentsOf: fixture.target.appendingPathComponent("a.mp3")) == before)
        #expect(!FileManager.default.fileExists(atPath: fixture.target.appendingPathComponent("a.flac").path))
    }

    @Test func hiddenSymlinksCannotEnterReplacement() throws {
        let fixture = try CollectionUpdateFixture()
        defer { fixture.remove() }
        try fixture.installInitial()
        let original = try Data(contentsOf: fixture.target.appendingPathComponent("a.mp3"))
        try FileManager.default.createSymbolicLink(at: fixture.target.appendingPathComponent(".link"), withDestinationURL: fixture.staging)
        let incoming = try fixture.stage([("a", "a.flac", "new audio")], quality: "flac")
        #expect(throws: OfflineLibraryError.self) { try fixture.commit(incoming, updating: true) }
        #expect(try Data(contentsOf: fixture.target.appendingPathComponent("a.mp3")) == original)
        #expect(!FileManager.default.fileExists(atPath: fixture.target.appendingPathComponent("a.flac").path))
    }
}

private struct CollectionUpdateFixture {
    let root: URL
    var staging: URL { root.appendingPathComponent("staging") }
    var library: URL { root.appendingPathComponent("library") }
    var target: URL { library.appendingPathComponent("collection") }
    init() throws {
        root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: staging, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: library, withIntermediateDirectories: true)
    }
    func remove() { try? FileManager.default.removeItem(at: root) }
    func installInitial() throws {
        let manifest = try stage([("a", "a.mp3", "original a"), ("b", "b.mp3", "original b")])
        _ = try commit(manifest, updating: false)
    }
    func stage(_ rows: [(String, String, String)], quality: String = "mp3_128", sourceID: String = "album") throws -> LibraryManifest {
        for file in try FileManager.default.contentsOfDirectory(at: staging, includingPropertiesForKeys: nil) {
            try FileManager.default.removeItem(at: file)
        }
        let entries = try rows.map { id, path, content -> LibraryManifest.Entry in
            try Data(content.utf8).write(to: staging.appendingPathComponent(path))
            let track = Track(discID: sourceID, number: id, title: id, artists: "Artist", albumTitle: "Album", coverURL: nil,
                              remoteSource: .init(providerID: "test", itemID: id))
            return .init(relativePath: path, itemID: id, track: track, quality: quality, requestedQuality: quality)
        }
        return LibraryManifest(source: .init(provider: "test", kind: "album", id: sourceID),
                               title: "Original collection", artist: "Artist", entries: entries,
                               extra: .object(["keep": .string("metadata")]))
    }
    func commit(_ manifest: LibraryManifest, updating: Bool) throws -> LibraryCollection? {
        try OfflineLibraryWorker.commitDirectory(staging: staging, folderName: "collection",
            provenance: updating ? .updatingCollection(manifest) : .collection(manifest, merge: true, preserving: [], placeholderMarker: nil), into: library)
    }
    func snapshot() throws -> [String: Data] {
        var result: [String: Data] = [:]
        let files = try #require(FileManager.default.enumerator(at: target, includingPropertiesForKeys: [.isRegularFileKey]))
        for case let url as URL in files where try url.resourceValues(forKeys: [.isRegularFileKey]).isRegularFile == true {
            result[try OfflinePaths.relativePath(of: url, inside: target)] = try Data(contentsOf: url)
        }
        return result
    }
}
