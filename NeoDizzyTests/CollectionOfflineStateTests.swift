import Foundation
import Testing
@testable import NeoDizzy

@MainActor struct CollectionOfflineStateTests {
    private func tracks(_ count: Int) -> [Track] {
        (1...count).map { Track(discID: "album", number: "\($0)", title: "歌曲", artists: "歌手", albumTitle: "专辑", coverURL: nil,
                                remoteSource: .init(providerID: "netease", itemID: "\($0)")) }
    }

    @Test func allDownloadedIsDownloaded() {
        #expect(CollectionOfflineState.resolve(tracks(3), isDownloaded: { _ in true }, isCached: { _ in false }) == .downloaded)
    }

    @Test func mixedDownloadedAndCachedIsCached() {
        let list = tracks(3)
        let state = CollectionOfflineState.resolve(list, isDownloaded: { $0.number == "1" }, isCached: { $0.number != "1" })
        #expect(state == .cached)
    }

    @Test func anyOnlineOnlySongShowsNothing() {
        let state = CollectionOfflineState.resolve(tracks(3), isDownloaded: { $0.number == "1" }, isCached: { $0.number == "2" })
        #expect(state == nil)
        #expect(CollectionOfflineState.resolve([], isDownloaded: { _ in true }, isCached: { _ in true }) == nil)
    }

    @Test func indexPersistsAndEvictsOldest() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let index = CollectionTrackIndex(directory: directory, capacity: 2)
        index.record("a", tracks: tracks(1))
        index.record("b", tracks: tracks(2))
        index.record("c", tracks: tracks(3))
        let reloaded = CollectionTrackIndex(directory: directory, capacity: 2)
        #expect(reloaded.tracks(for: "a") == nil)
        #expect(reloaded.tracks(for: "c")?.count == 3)
    }
}
