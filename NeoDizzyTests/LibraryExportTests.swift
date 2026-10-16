import Foundation
import Testing
@testable import NeoDizzy

@MainActor struct LibraryExportTests {
    @Test func exportPreservesOrderDuplicatesAndExplicitCompleteness() throws {
        func track(_ provider: String, _ number: String) -> Track {
            Track(discID: "album", number: number, title: "相同歌曲", artists: "作者", albumTitle: "专辑", coverURL: URL(string: "https://example.com/cover?token=secret"),
                  remoteSource: .init(providerID: provider, itemID: number))
        }
        let songs = [track("netease", "90"), track("qq", "90"), track("netease", "1")].map { LibraryExport.Song($0) }
        let export = LibraryExport(exportedAt: .now, favorites: songs, savedSongs: [], collections: [
            .init(providerID: "netease", kind: "playlist", itemID: "p", title: "歌单", subtitle: "", songs: [], songsComplete: false, issue: "未能读取")
        ])
        let data = try export.data()
        let decoder = JSONDecoder(); decoder.dateDecodingStrategy = .iso8601
        let restored = try decoder.decode(LibraryExport.self, from: data)
        #expect(restored.version == 1)
        #expect(restored.favorites.map(\.itemID) == ["90", "90", "1"])
        #expect(restored.favorites.map(\.providerID) == ["netease", "qq", "netease"])
        #expect(restored.collections.first?.songsComplete == false)
        #expect(!String(decoding: data, as: UTF8.self).contains("secret"))
    }

    @Test func exportExcludesSandboxPathsAndIncludesLocalMetadata() throws {
        let song = Track(discID: "/private/container/album", number: "2", title: "歌曲", artists: "歌手", albumTitle: "专辑", coverURL: URL(fileURLWithPath: "/private/container/cover.png"), duration: 123,
                         localSource: .init(albumID: "album", trackID: "/private/container/song.flac"))
        let export = LibraryExport(exportedAt: .now, favorites: [.init(song)], savedSongs: [], collections: [])
        let text = String(decoding: try export.data(), as: UTF8.self)
        #expect(!text.contains("/private/"))
        #expect(!text.contains("cover.png"))
        #expect(text.contains("song.flac"))
        #expect(text.contains("123"))
    }
}
