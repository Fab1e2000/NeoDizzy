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
        #expect(issues.count == 4)
        // 歌单目录中的音频不成为专辑，也不能借内部符号链接绕过校验。
        try Data("extra".utf8).write(to: root.appendingPathComponent("Playlists/hidden.mp3"))
        try FileManager.default.createSymbolicLink(at: root.appendingPathComponent("Alias"), withDestinationURL: root.appendingPathComponent("Album"))
        #expect(throws: (any Error).self) { try LocalPlaylistFile.resolve("../Alias/song.mp3", root: root) }
        let scanner = LocalLibraryScanner(cacheURL: root.appendingPathComponent(".cache"), readMetadata: { _ in AudioMetadata(title: "歌曲") })
        let result = try await scanner.scan([OfflineFolderAccess(url: root)], excluding: [])
        #expect(result.albums.count == 1)
        #expect(result.albums.first?.tracks.count == 1)
        #expect(result.playlists.first?.tracks.count == 1)
        #expect(result.issues.count == 4)
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
