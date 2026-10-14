import Testing
@testable import NeoDizzy
import Foundation

@Suite @MainActor
struct LibraryManifestTests {
    private func track(_ provider: String) -> Track {
        Track(discID: "album", number: "1", title: "歌曲", artists: "歌手", albumTitle: "专辑", coverURL: nil,
              remoteSource: provider == "dizzylab" ? nil : RemoteTrackSource(providerID: provider, itemID: "123"))
    }

    @Test func legacyReadDoesNotRewriteFiles() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let old = Data(#"{"version":1,"discID":"album","title":"专辑","labelName":"社团","releaseDate":"2020","description":"介绍","credits":"制作","labelDescription":"简介","entries":[{"relativePath":"01.wav","track":{"discID":"album","number":"1","title":"歌曲","artists":"歌手","albumTitle":"专辑"}}]}"#.utf8)
        let audio = Data("untouched".utf8)
        try old.write(to: root.appendingPathComponent(LibraryManifest.filename))
        try audio.write(to: root.appendingPathComponent("01.wav"))
        let result = try OfflineLibraryWorker.scanDirectory(root)
        let record = try #require(result.albums.first)
        #expect(record.manifest.version == 2)
        #expect(record.manifest.source == LibrarySource(provider: "dizzylab", kind: "album", id: "album"))
        #expect(record.manifest.entries.first?.itemID == "album/1")
        #expect(record.detail.description == "介绍")
        #expect(record.detail.releaseDate == "2020")
        #expect(try Data(contentsOf: root.appendingPathComponent(LibraryManifest.filename)) == old)
        #expect(try Data(contentsOf: root.appendingPathComponent("01.wav")) == audio)
    }

    @Test func explicitRedownloadPreservesLegacyManifestOriginal() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let source = root.appendingPathComponent("source")
        let destination = root.appendingPathComponent("library")
        try FileManager.default.createDirectory(at: source, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: destination, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let song = track("dizzylab")
        let detail = DiscDetail(summary: DiscSummary(id: "album", title: "专辑", coverURL: nil), releaseDate: nil,
                                description: "", credits: "", labelDescription: "", hasGift: false, tracks: [song], streams: [:])
        try Data("original".utf8).write(to: source.appendingPathComponent("01.wav"))
        let first = try OfflineLibraryWorker.importDirectory(from: source, detail: detail, into: destination)
        let file = first.directoryURL.appendingPathComponent(LibraryManifest.filename)
        let old = Data(#"{"version":1,"discID":"album","title":"旧标题","labelName":"旧社团","description":"旧介绍","credits":"","labelDescription":"","entries":[{"relativePath":"01.wav","track":{"discID":"album","number":"1","title":"歌曲","artists":"歌手","albumTitle":"专辑"}}]}"#.utf8)
        try old.write(to: file)
        let inode = try FileManager.default.attributesOfItem(atPath: file.path)[.systemFileNumber] as? NSNumber
        try Data("replacement".utf8).write(to: source.appendingPathComponent("01.wav"))
        let second = try OfflineLibraryWorker.importDirectory(from: source, detail: detail, into: destination)
        #expect(try Data(contentsOf: file) == old)
        #expect(try FileManager.default.attributesOfItem(atPath: file.path)[.systemFileNumber] as? NSNumber == inode)
        #expect(second.title == "旧标题")
        #expect(try Data(contentsOf: second.directoryURL.appendingPathComponent("01.wav")) == Data("replacement".utf8))
    }

    @Test func versionTwoRoundTripsOpaqueExtraAndQuality() throws {
        let song = track("netease")
        let extra: LibraryJSON = .object(["nested": .array([.bool(true), .null, .number(42), .object(["text": .string("保留")])])])
        let manifest = LibraryManifest(source: LibrarySource(provider: "netease", kind: "album", id: "album"),
            title: "专辑", artist: "歌手", entries: [.init(relativePath: "01.wav", itemID: "123", track: song, quality: "lossless")], extra: extra)
        let restored = try JSONDecoder().decode(LibraryManifest.self, from: JSONEncoder().encode(manifest))
        #expect(restored.extra == extra)
        #expect(restored.source == manifest.source)
        #expect(restored.entries.first?.quality == "lossless")
        #expect(restored.entries.first?.track == song)
    }

    @Test func bothProvidersResolveLocalFilesAndNeteaseBypassesNetwork() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let suite = "LibraryManifestTests.\(UUID())"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer {
            defaults.removePersistentDomain(forName: suite)
            try? FileManager.default.removeItem(at: root)
        }
        for provider in ["dizzylab", "netease"] {
            let directory = root.appendingPathComponent(provider)
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            try Data("audio".utf8).write(to: directory.appendingPathComponent("01.wav"))
            let song = track(provider)
            let key = try #require(song.remoteKey)
            let manifest = LibraryManifest(source: LibrarySource(provider: provider, kind: "album", id: "album"),
                title: "专辑", artist: "歌手", entries: [.init(relativePath: "01.wav", itemID: key.itemID, track: song)])
            try JSONEncoder().encode(manifest).write(to: directory.appendingPathComponent(LibraryManifest.filename))
        }
        let scanner = LocalLibraryScanner(cacheURL: root.appendingPathComponent(".cache"), readMetadata: { _ in AudioMetadata() })
        let library = OfflineLibraryStore(defaults: defaults, scanner: scanner)
        try await library.selectFolder(root)
        #expect(library.collections.count == 2)
        for provider in ["dizzylab", "netease"] {
            let song = track(provider)
            #expect(library.localFile(for: song)?.deletingLastPathComponent().lastPathComponent == provider)
            #expect(library.access(for: song) != nil)
            #expect(try await library.localTrackKeys(provider: provider, collectionID: "album") == [song.remoteKey!])
        }
        let resolver = StreamResolver(fetch: { _ in Issue.record("不应请求网络"); return [:] },
                                      localFile: { library.localFile(for: $0) }, localAccess: { library.access(for: $0) })
        resolver.register("netease", stream: { _ in Issue.record("不应请求网络"); throw PlaybackError.unavailable }, lyrics: { _ in throw PlaybackError.unavailable })
        let song = track("netease")
        #expect(resolver.localURL(for: song)?.isFileURL == true)
        let file = try await resolver.stream(for: song)
        #expect(file.isFileURL)
        #expect(!resolver.isPreview(for: song, url: file))
        try FileManager.default.removeItem(at: file)
        #expect(library.localFile(for: song) == nil)
        #expect(try await library.localTrackKeys(provider: "netease", collectionID: "album").isEmpty)
    }
}
