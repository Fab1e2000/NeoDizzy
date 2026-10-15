import Foundation
import Testing
@testable import NeoDizzy

@MainActor struct NeteaseAlbumDirectoryMigrationTests {
    @Test func renamesExistingDownloadAndPreservesPlaylistAudioAndCustomDirectories() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let old = root.appendingPathComponent("歌手 - 专辑")
        try FileManager.default.createDirectory(at: old, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let track = Track(discID: "7", number: "1", title: "歌曲", artists: "歌手", albumTitle: "专辑", coverURL: nil,
                          remoteSource: RemoteTrackSource(providerID: "netease", itemID: "42"))
        let manifest = LibraryManifest(source: LibrarySource(provider: "netease", kind: "album", id: "7"), title: "专辑", artist: "歌手",
                                       entries: [.init(relativePath: "01.flac", itemID: "42", track: track, quality: "lossless")])
        let original = try Fixture.data("audio-local-tags.flac")
        try original.write(to: old.appendingPathComponent("01.flac"))
        try JSONEncoder().encode(manifest).write(to: old.appendingPathComponent(LibraryManifest.filename))
        try LocalPlaylistFile.write(title: "收藏", entries: [(track, old.appendingPathComponent("01.flac"))], source: nil, existing: nil, root: root)
        let worker = OfflineLibraryWorker()
        let result = try await worker.scan(OfflineFolderAccess(url: root))
        let album = try #require(result.albums.first)
        #expect(album.directoryURL.lastPathComponent == "专辑")
        #expect(!FileManager.default.fileExists(atPath: old.path))
        let audio = root.appendingPathComponent("专辑/01.flac")
        #expect(try Data(contentsOf: audio) == original)
        let playlist = try LocalPlaylistFile.read(root.appendingPathComponent("Playlists/收藏.m3u8"), root: root,
                                                  tracks: [LocalLibraryScanner.canonical(audio): track])
        #expect(playlist.0.tracks.count == 1)
        #expect(playlist.1.isEmpty)
        let again = try await worker.scan(OfflineFolderAccess(url: root))
        #expect(again.albums.count == 1)
        let custom = LibraryCollection(manifest: manifest, directoryURL: root.appendingPathComponent("自定义名称"))
        #expect(!OfflineLibraryWorker.hasLegacyNeteaseName(custom))
    }

    @Test func neverOverwritesExistingAlbumDirectory() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let old = root.appendingPathComponent("歌手 - 专辑")
        let target = root.appendingPathComponent("专辑")
        try FileManager.default.createDirectory(at: old, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: target, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let sentinel = target.appendingPathComponent("keep.txt")
        try Data("保留".utf8).write(to: sentinel)
        let manifest = LibraryManifest(source: LibrarySource(provider: "netease", kind: "album", id: "7"), title: "专辑", artist: "歌手", entries: [])
        let changed = try OfflineLibraryWorker.migrateNeteaseAlbumNames([LibraryCollection(manifest: manifest, directoryURL: old)], in: root)
        #expect(!changed)
        #expect(FileManager.default.fileExists(atPath: old.path))
        #expect(try Data(contentsOf: sentinel) == Data("保留".utf8))
    }
}
