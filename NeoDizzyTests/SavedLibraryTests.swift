import Foundation
import Testing
@testable import NeoDizzy

@MainActor
struct SavedLibraryTests {
    private func directory() -> URL {
        FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
    }

    private var track: Track {
        Track(discID: "", number: "1", title: "歌曲", artists: "歌手甲, 歌手乙", albumTitle: "专辑", coverURL: nil,
              remoteSource: RemoteTrackSource(providerID: "netease", itemID: "42"))
    }

    @Test func addingTwiceKeepsOneItemAndTheFirstDate() {
        let folder = directory()
        defer { try? FileManager.default.removeItem(at: folder) }
        let store = SavedLibraryStore(directory: folder)
        let first = Date(timeIntervalSince1970: 100)
        store.add(.song(track, providerID: "netease", itemID: "42", addedAt: first))
        store.add(.song(track, providerID: "netease", itemID: "42", addedAt: .now))
        #expect(store.items.count == 1)
        #expect(store.items.first?.addedAt == first)
        #expect(store.contains(.song, providerID: "netease", itemID: "42"))
        #expect(!store.contains(.album, providerID: "netease", itemID: "42"))
    }

    @Test func itemsSurviveARestartAndCanBeRemoved() {
        let folder = directory()
        defer { try? FileManager.default.removeItem(at: folder) }
        let album = SavedLibraryItem(kind: .album, providerID: "dizzylab", itemID: "abc", title: "专辑", subtitle: "社团",
                                     coverURL: nil, addedAt: .now)
        let store = SavedLibraryStore(directory: folder)
        store.add(.song(track, providerID: "netease", itemID: "42"))
        store.add(album)

        let reopened = SavedLibraryStore(directory: folder)
        #expect(reopened.items.map(\.id) == [album.id, "song/netease/42"])
        #expect(reopened.items(of: .song).first?.track == track)

        reopened.toggle(album)
        #expect(SavedLibraryStore(directory: folder).items.map(\.id) == ["song/netease/42"])
    }

    @Test func artistNamesSplitCommonSeparators() {
        let track = Track(discID: "", number: "1", title: "歌", artists: "甲, 乙/丙、丁，戊", albumTitle: "", coverURL: nil)
        #expect(LibraryContents.artistNames(track) == ["甲", "乙", "丙", "丁", "戊"])
        let unnamed = Track(discID: "", number: "1", title: "歌", artists: " ", albumTitle: "", coverURL: nil)
        #expect(LibraryContents.artistNames(unnamed) == ["未知歌手"])
    }
}
