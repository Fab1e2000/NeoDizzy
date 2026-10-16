import Foundation
import Testing
@testable import NeoDizzy

@MainActor struct FavoritesTests {
    private func track(_ provider: String = "netease", _ id: String = "1") -> Track {
        Track(discID: "album", number: id, title: "相同歌曲", artists: "相同歌手", albumTitle: "专辑", coverURL: nil,
              remoteSource: RemoteTrackSource(providerID: provider, itemID: id))
    }
    private func directory() -> URL { FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString) }
    private enum Failure: Error { case network }

    @Test func legacySavedSongsMigrateOnceWithoutLosingCollectionsOrRevivingUnlikes() async throws {
        let folder = directory(); defer { try? FileManager.default.removeItem(at: folder) }
        let saved = SavedLibraryStore(directory: folder)
        let song = Track(discID: "disc", number: "1", title: "Old", artists: "", albumTitle: "", coverURL: nil)
        let date = Date(timeIntervalSince1970: 100)
        let legacy = SavedLibraryItem.song(song, providerID: "dizzylab", itemID: song.id, addedAt: date)
        saved.add(legacy)
        let album = SavedLibraryItem(kind: .album, providerID: "dizzylab", itemID: "disc", title: "Album", subtitle: "", coverURL: nil, addedAt: date)
        saved.add(album)
        let store = FavoritesStore(directory: folder)
        store.migrateSavedSongs(from: saved)
        #expect(store.songs.count == 1)
        #expect(store.songs.first?.addedAt == date)
        #expect(saved.items == [album])
        #expect(SavedLibraryStore(directory: folder).items == [album])
        try await store.setLiked(song, false)
        saved.add(legacy) // Simulate cleanup failure or a restored legacy file.
        let restored = FavoritesStore(directory: folder)
        restored.migrateSavedSongs(from: saved)
        #expect(restored.songs.isEmpty)
        #expect(saved.items == [album])
    }

    @Test func legacyMigrationMergesExistingLikesAndPreservesSourceOnFailure() async throws {
        let folder = directory(); defer { try? FileManager.default.removeItem(at: folder) }
        let saved = SavedLibraryStore(directory: folder)
        let song = Track(discID: "disc", number: "1", title: "Old", artists: "", albumTitle: "", coverURL: nil)
        saved.add(.song(song, providerID: "dizzylab", itemID: song.id, addedAt: .distantPast))
        let store = FavoritesStore(directory: folder)
        try await store.setLiked(song, true)
        let timestamp = store.songs.first?.addedAt
        store.migrateSavedSongs(from: saved)
        #expect(store.songs.count == 1)
        #expect(store.songs.first?.addedAt == timestamp)

        let other = folder.appendingPathComponent("broken")
        let failing = FavoritesStore(directory: other)
        try FileManager.default.removeItem(at: other)
        try Data().write(to: other) // Make database directory inaccessible as a directory.
        saved.add(.song(song, providerID: "dizzylab", itemID: song.id))
        failing.migrateSavedSongs(from: saved)
        #expect(saved.items(of: .song).count == 1)
        #expect(failing.songs.isEmpty)
        #expect(failing.errors["storage"] != nil)
    }

    @Test func crossProviderDuplicatesAndLocalLikesPersist() async throws {
        let folder = directory(); defer { try? FileManager.default.removeItem(at: folder) }
        let store = FavoritesStore(directory: folder)
        for provider in ["netease", "qq"] {
            let song = track(provider)
            store.register(provider, provider: FavoritesProvider(account: { "account" }, load: { [song, song] }, setLiked: { _, _ in }))
        }
        await store.refresh()
        #expect(store.songs.count == 2)
        #expect(Set(store.songs.map(\.id)) == ["netease/1", "qq/1"])
        try await store.setLiked(track(), false)
        #expect(store.songs.map(\.providerID) == ["qq"])
        let local = Track(discID: "", number: "1", title: "本地", artists: "", albumTitle: "", coverURL: nil,
                          localSource: LocalTrackSource(albumID: "a", trackID: "b"))
        try await store.setLiked(local, true)
        let restored = FavoritesStore(directory: folder)
        #expect(restored.contains(local))
        restored.register("qq", provider: FavoritesProvider(account: { "account" }, load: { [] }, setLiked: { _, _ in }))
        #expect(restored.songs.count == 2)
    }

    @Test func failedWritesAndReadsKeepConfirmedState() async throws {
        let folder = directory(); defer { try? FileManager.default.removeItem(at: folder) }
        let store = FavoritesStore(directory: folder), song = track()
        var fail = false
        store.register("netease", provider: FavoritesProvider(account: { "a" }, load: {
            if fail { throw Failure.network }; return [song]
        }, setLiked: { _, _ in throw Failure.network }))
        await store.refresh()
        do { try await store.setLiked(song, false); Issue.record("Write should fail") } catch { }
        #expect(store.contains(song))
        fail = true; await store.refresh()
        #expect(store.contains(song)); #expect(store.errors["netease"] != nil)
    }

    @Test func accountSwitchAndLogoutHideOtherAccounts() async throws {
        let folder = directory(); defer { try? FileManager.default.removeItem(at: folder) }
        let store = FavoritesStore(directory: folder), song = track()
        var account: String? = "a"
        store.register("netease", provider: FavoritesProvider(account: { account }, load: { [song] }, setLiked: { _, _ in }))
        await store.refresh()
        account = "b"; store.updateAccounts(); #expect(store.songs.isEmpty)
        account = "a"; store.updateAccounts(); #expect(store.contains(song))
        account = nil; store.updateAccounts(); #expect(store.songs.isEmpty)
    }

    @Test func staleRefreshCannotOverwriteSuccessfulMutation() async throws {
        let folder = directory(); defer { try? FileManager.default.removeItem(at: folder) }
        let store = FavoritesStore(directory: folder), song = track()
        var continuation: CheckedContinuation<[Track], Never>?
        var loads = 0
        store.register("netease", provider: FavoritesProvider(account: { "a" }, load: {
            loads += 1
            if loads == 1 { return await withCheckedContinuation { continuation = $0 } }
            return [song]
        }, setLiked: { _, _ in }))
        let reading = Task { await store.refresh() }
        while continuation == nil { await Task.yield() }
        try await store.setLiked(song, true)
        continuation?.resume(returning: [])
        await reading.value
        #expect(store.contains(song)); #expect(loads == 2)
    }

    @Test func migrationNeverResurrectsAnUnlikedSong() async throws {
        let folder = directory(); defer { try? FileManager.default.removeItem(at: folder) }
        let store = FavoritesStore(directory: folder), song = track()
        store.register("netease", provider: FavoritesProvider(account: { "a" }, load: { [] }, setLiked: { _, _ in }))
        store.migrate(providerID: "netease", account: "a", tracks: [song])
        #expect(store.contains(song))
        try await store.setLiked(song, false)
        store.migrate(providerID: "netease", account: "a", tracks: [song])
        #expect(store.songs.isEmpty)
    }
    @Test func serverOrderWinsOverTagsAndNewLikesLeadAcrossSources() async throws {
        let folder = directory(); defer { try? FileManager.default.removeItem(at: folder) }
        let store = FavoritesStore(directory: folder)
        let first = track("netease", "90"), second = track("netease", "1")
        var response = [first, second]
        store.register("netease", provider: FavoritesProvider(account: { "a" }, load: { response }, setLiked: { _, _ in }))
        await store.refresh()
        #expect(store.songs.map(\.itemID) == ["90", "1"])
        response = [second, first]
        await store.refresh()
        #expect(store.songs.map(\.itemID) == ["1", "90"])
        let local = Track(discID: "", number: "400", title: "Z", artists: "", albumTitle: "", coverURL: nil,
                          localSource: .init(albumID: "a", trackID: "local"))
        try await store.setLiked(local, true)
        #expect(store.songs.first?.id == "local/local")
        try await store.setLiked(first, true)
        #expect(store.songs.first?.id == "netease/90")
        let restored = FavoritesStore(directory: folder)
        restored.register("netease", provider: FavoritesProvider(account: { "a" }, load: { [] }, setLiked: { _, _ in }))
        #expect(restored.songs.map(\.id) == store.songs.map(\.id))
    }

    @Test func legacyFavoritesDecodeWithoutAddedDate() throws {
        let original = FavoriteSong(track: track())
        let data = try JSONEncoder().encode(original)
        let restored = try JSONDecoder().decode(FavoriteSong.self, from: data)
        #expect(restored.addedAt == nil)
        #expect(restored.id == original.id)
    }

}
