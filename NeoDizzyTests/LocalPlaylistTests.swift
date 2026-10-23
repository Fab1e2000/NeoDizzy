import Foundation
import Testing
@testable import NeoDizzy

struct LocalPlaylistTests {
    private func folder() throws -> URL {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root.appendingPathComponent("Album"), withIntermediateDirectories: true)
        try Data("audio".utf8).write(to: root.appendingPathComponent("Album/song.mp3"))
        return root
    }

    @Test func additionalProviderPlaylistRoundTripsAndRejectsInjectedHeaders() throws {
        let root = try folder()
        defer { try? FileManager.default.removeItem(at: root) }
        let track = Track(discID: "", number: "1", title: "歌曲", artists: "歌手", albumTitle: "Album", coverURL: nil)
        let audio = root.appendingPathComponent("Album/song.mp3")
        let source = LibrarySource(provider: "qqmusic", kind: "playlist", id: "mid_123")
        try LocalPlaylistFile.write(title: "QQ", entries: [(track, audio)], source: source, existing: nil, root: root)
        let file = root.appendingPathComponent("Playlists/QQ.m3u8")
        let (playlist, issues) = try LocalPlaylistFile.read(file, root: root, tracks: [LocalLibraryScanner.canonical(audio): track])
        #expect(playlist.source == source)
        #expect(playlist.tracks.map(\.id) == [track.id])
        #expect(issues.isEmpty)
        for provider in ["", "qq:music", "qq\nmusic", "qq\0music"] {
            #expect(throws: (any Error).self) {
                try LocalPlaylistFile.write(title: "Invalid", entries: [],
                                            source: LibrarySource(provider: provider, kind: "playlist", id: "123"), existing: nil, root: root)
            }
        }
        for id in ["", "12:3", "12\n3", "12\0" ] {
            #expect(throws: (any Error).self) {
                try LocalPlaylistFile.write(title: "Invalid", entries: [],
                                            source: LibrarySource(provider: "qqmusic", kind: "playlist", id: id), existing: nil, root: root)
            }
        }
    }

    @Test func roundTripPreservesOrderSourceAndSkipsUnsafeOrMissingReferences() async throws {
        let root = try folder()
        defer { try? FileManager.default.removeItem(at: root) }
        let track = Track(discID: "", number: "1", title: "歌曲", artists: "歌手", albumTitle: "Album", coverURL: nil)
        let audio = root.appendingPathComponent("Album/song.mp3")
        let source = LibrarySource(provider: "netease", kind: "playlist", id: "123")
        try LocalPlaylistFile.write(title: "我的歌单", entries: [(track, audio)], source: source, existing: nil, root: root)
        let file = root.appendingPathComponent("Playlists/我的歌单.m3u8")
        let text = try String(contentsOf: file, encoding: .utf8)
        #expect(text.contains("#EXTM3U\n#NEODIZZY-SOURCE:netease:playlist:123\n#EXTINF:-1,歌曲\n../Album/song.mp3"))
        try Data((text + "../../outside.mp3\n../missing.mp3\nhttps://host/song.mp3\n/Album/song.mp3\n").utf8).write(to: file)
        let (playlist, issues) = try LocalPlaylistFile.read(file, root: root, tracks: [LocalLibraryScanner.canonical(audio): track])
        #expect(playlist.tracks.map(\.id) == [track.id])
        #expect(playlist.source == source)
        #expect(issues.count == 3)
        // 歌单目录中的音频不成为专辑，也不能借内部符号链接绕过校验。
        try Data("extra".utf8).write(to: root.appendingPathComponent("Playlists/hidden.mp3"))
        try FileManager.default.createSymbolicLink(at: root.appendingPathComponent("Alias"), withDestinationURL: root.appendingPathComponent("Album"))
        #expect(throws: (any Error).self) { try LocalPlaylistFile.resolve("../Alias/song.mp3", root: root) }
        let scanner = LocalLibraryScanner(cacheURL: root.appendingPathComponent(".cache"), readMetadata: { _ in AudioMetadata(title: "歌曲") })
        let result = try await scanner.scan([OfflineFolderAccess(url: root)], excluding: [])
        #expect(result.albums.count == 1)
        #expect(result.albums.first?.tracks.count == 1)
        #expect(result.playlists.first?.tracks.count == 1)
        #expect(result.issues.count == 3)
    }

    @Test @MainActor func deletesAlbumAudioAndRefreshesLibraryWithoutRemovingOtherFiles() async throws {
        let root = try folder()
        defer { try? FileManager.default.removeItem(at: root) }
        let cover = root.appendingPathComponent("Album/cover.jpg")
        try Data("cover".utf8).write(to: cover)
        let nested = root.appendingPathComponent("Album/Nested")
        try FileManager.default.createDirectory(at: nested, withIntermediateDirectories: true)
        let other = nested.appendingPathComponent("other.mp3")
        try Data("other".utf8).write(to: other)
        let suite = "AlbumDeletion.\(UUID())"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let scanner = LocalLibraryScanner(cacheURL: root.appendingPathComponent(".cache"), readMetadata: { _ in AudioMetadata(title: "歌曲") })
        let library = OfflineLibraryStore(defaults: defaults, scanner: scanner, libraryRoot: root)
        await library.restore()
        let album = try #require(library.localAlbums.first { $0.entries.contains { $0.fileURL.lastPathComponent == "song.mp3" } })
        try await library.deleteAlbum(album)
        #expect(library.localAlbum(id: album.id) == nil)
        #expect(!FileManager.default.fileExists(atPath: root.appendingPathComponent("Album/song.mp3").path))
        #expect(FileManager.default.fileExists(atPath: cover.path))
        #expect(FileManager.default.fileExists(atPath: other.path))
        #expect(library.localAlbums.count == 1)
    }

    @Test @MainActor func batchDeletionRemovesOnlySelectedAlbums() async throws {
        let root = try folder()
        defer { try? FileManager.default.removeItem(at: root) }
        for name in ["Second", "Keep"] {
            let directory = root.appendingPathComponent(name)
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            try Data("audio".utf8).write(to: directory.appendingPathComponent("song.mp3"))
        }
        let suite = "BatchDeletion.\(UUID())"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let scanner = LocalLibraryScanner(cacheURL: root.appendingPathComponent(".cache"), readMetadata: { _ in AudioMetadata(title: "歌曲") })
        let library = OfflineLibraryStore(defaults: defaults, scanner: scanner, libraryRoot: root)
        await library.restore()
        #expect(library.localAlbums.count == 3)
        let selected = library.localAlbums.filter { $0.entries.first?.fileURL.deletingLastPathComponent().lastPathComponent != "Keep" }
        try await library.deleteAlbums(ids: Set(selected.map(\.id)))
        #expect(library.localAlbums.count == 1)
        #expect(FileManager.default.fileExists(atPath: root.appendingPathComponent("Keep/song.mp3").path))
        #expect(!FileManager.default.fileExists(atPath: root.appendingPathComponent("Album/song.mp3").path))
        #expect(!FileManager.default.fileExists(atPath: root.appendingPathComponent("Second/song.mp3").path))
    }

    @Test func albumDeletionRejectsUnsafeTargetsBeforeDeletingAnyFiles() async throws {
        let root = try folder()
        defer { try? FileManager.default.removeItem(at: root) }
        let song = root.appendingPathComponent("Album/song.mp3")
        let alias = root.appendingPathComponent("alias.mp3")
        try FileManager.default.createSymbolicLink(at: alias, withDestinationURL: song)
        let worker = OfflineLibraryWorker()
        for invalid in [alias, root.appendingPathComponent("Album"), root.deletingLastPathComponent().appendingPathComponent("outside.mp3")] {
            await #expect(throws: (any Error).self) {
                try await worker.deleteAlbumFiles([song, invalid], access: OfflineFolderAccess(url: root))
            }
            #expect(FileManager.default.fileExists(atPath: song.path))
        }
    }

    @Test @MainActor func createAppendDeleteNeverChangesAudioAndSourcePlaylistUpdatesInPlace() async throws {
        let root = try folder()
        defer { try? FileManager.default.removeItem(at: root) }
        let suite = "PlaylistTests.\(UUID())"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let scanner = LocalLibraryScanner(cacheURL: root.appendingPathComponent(".cache"), readMetadata: { _ in AudioMetadata(title: "歌曲") })
        let library = OfflineLibraryStore(defaults: defaults, scanner: scanner, libraryRoot: root)
        await library.restore()
        let track = try #require(library.localAlbums.first?.tracks.first)
        try await library.savePlaylist(title: "歌单", tracks: [])
        let empty = try #require(library.localPlaylists.first)
        try await library.add(track, to: empty)
        let filled = try #require(library.localPlaylists.first)
        #expect(filled.tracks.count == 1)
        try await library.add(track, to: filled)
        #expect(library.localPlaylists.first?.tracks.count == 1)
        try await library.deletePlaylist(filled)
        #expect(library.localPlaylists.isEmpty)
        #expect(try Data(contentsOf: root.appendingPathComponent("Album/song.mp3")) == Data("audio".utf8))
        let source = LibrarySource(provider: "netease", kind: "playlist", id: "123")
        try await library.savePlaylist(title: "网络歌单", tracks: [track], source: source)
        let id = try #require(library.localPlaylists.first?.id)
        try await library.savePlaylist(title: "新名字", tracks: [track], source: source)
        #expect(library.localPlaylists.count == 1)
        #expect(library.localPlaylists.first?.id == id)
    }

    @Test func conflictingNameAndEscapingWritesLeaveOriginalUntouched() throws {
        let root = try folder()
        defer { try? FileManager.default.removeItem(at: root) }
        try LocalPlaylistFile.write(title: "歌单", entries: [], source: nil, existing: nil, root: root)
        let file = root.appendingPathComponent("Playlists/歌单.m3u8")
        let before = try Data(contentsOf: file)
        #expect(throws: OfflineLibraryError.existingAlbum) {
            try LocalPlaylistFile.write(title: "歌单", entries: [], source: nil, existing: nil, root: root)
        }
        #expect(throws: (any Error).self) {
            try LocalPlaylistFile.write(title: "bad", entries: [], source: nil, existing: root.appendingPathComponent("Album/song.mp3"), root: root)
        }
        #expect(try Data(contentsOf: file) == before)
    }
}
