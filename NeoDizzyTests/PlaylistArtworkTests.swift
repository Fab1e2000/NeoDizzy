import Foundation
import Testing
@testable import NeoDizzy

@MainActor struct PlaylistArtworkTests {
    @Test func repairsExistingPlaylistAndKeepsArtworkAfterAddingAndRescanning() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let folder = root.appendingPathComponent("歌单/收藏")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let suite = "PlaylistArtwork.\(UUID())"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let songCover = URL(string: "https://example.com/song.jpg")!
        let playlistCover = URL(string: "https://example.com/playlist.jpg")!
        let track = Track(discID: "7", number: "1", title: "歌曲", artists: "歌手", albumTitle: "专辑", coverURL: songCover,
                          remoteSource: RemoteTrackSource(providerID: "netease", itemID: "42"))
        let manifest = LibraryManifest(source: LibrarySource(provider: "netease", kind: "playlist", id: "99"), title: "收藏", artist: "歌手",
            artworkURL: songCover, entries: [.init(relativePath: "01.flac", itemID: "42", track: track)])
        let audio = try Fixture.data("audio-local-tags.flac")
        try audio.write(to: folder.appendingPathComponent("01.flac"))
        try JSONEncoder().encode(manifest).write(to: folder.appendingPathComponent(LibraryManifest.filename))
        let library = OfflineLibraryStore(defaults: defaults,
            scanner: LocalLibraryScanner(cacheURL: root.appendingPathComponent(".cache")), libraryRoot: root)
        await library.restore()
        try await library.repairPlaylistArtwork(["99": playlistCover], providerID: "netease")
        let playlist = try #require(library.localPlaylists.first)
        #expect(playlist.coverURL == playlistCover)
        #expect(library.visibleAlbums.isEmpty)
        try await library.add(try #require(playlist.tracks.first), to: playlist)
        await library.scan()
        #expect(library.localPlaylists.first?.coverURL == playlistCover)
        let saved = try JSONDecoder().decode(LibraryManifest.self, from: Data(contentsOf: folder.appendingPathComponent(LibraryManifest.filename)))
        #expect(saved.artworkURL == playlistCover)
        #expect(saved.entries.first?.track.coverURL == songCover)
        #expect(try Data(contentsOf: folder.appendingPathComponent("01.flac")) == audio)
        // An already correct playlist cover is not replaced by a stale queue thumbnail.
        try await library.repairPlaylistArtwork(["99": URL(string: "https://example.com/old.jpg")!], providerID: "netease")
        #expect(library.localPlaylists.first?.coverURL == playlistCover)
    }
}
