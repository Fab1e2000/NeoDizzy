import Testing
@testable import NeoDizzy

struct SongLibraryActionsTests {
    private func track(provider: String? = nil, id: String = "42", local: Bool = false) -> Track {
        Track(discID: "album", number: "1", title: "Song", artists: "Artist", albumTitle: "Album", coverURL: nil,
              localSource: local ? LocalTrackSource(albumID: "album", trackID: "local-song") : nil,
              remoteSource: provider.map { RemoteTrackSource(providerID: $0, itemID: id) })
    }

    @Test func downloadedNeteaseKeepsPlatformIdentity() {
        let song = track(provider: "netease", local: true)
        #expect(SongPlaylistDestination.resolve(song, hasLocalFile: true) == .netease(42))
        #expect(SongPlaylistDestination.resolve(song, hasLocalFile: false) == .netease(42))
    }

    @Test func localAndDizzyLabRequireAnAvailableFile() {
        for song in [track(local: true), track(), track(provider: "qq")] {
            #expect(SongPlaylistDestination.resolve(song, hasLocalFile: true) == .local)
            #expect(SongPlaylistDestination.resolve(song, hasLocalFile: false) == .unavailable)
        }
    }

    @Test func invalidRemoteIDCannotOpenPlatformPicker() {
        #expect(SongPlaylistDestination.resolve(track(provider: "netease", id: "invalid"), hasLocalFile: false) == .unavailable)
    }
}
