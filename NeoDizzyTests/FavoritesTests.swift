import Foundation
import Observation
import Synchronization
import Testing
@testable import NeoDizzy

@MainActor struct FavoritesTests {
    private func track(_ provider: String = "netease", _ id: String = "1") -> Track {
        Track(discID: "album", number: id, title: "相同歌曲", artists: "相同歌手", albumTitle: "专辑", coverURL: nil,
              remoteSource: RemoteTrackSource(providerID: provider, itemID: id))
    }
    private func directory() -> URL { FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString) }
    private enum Failure: Error { case network }

    @Test func accountLikesKeepRestoredTimesAfterResync() async throws {
        let folder = directory(); defer { try? FileManager.default.removeItem(at: folder) }
        let store = FavoritesStore(directory: folder)
        let now = Date.now
        let dizzy = Track(discID: "disc", number: "1", title: "Dizzy", artists: "", albumTitle: "", coverURL: nil)
        _ = try store.importDeviceSongs([FavoriteSong(track: dizzy, addedAt: now.addingTimeInterval(-3600))])
        // 备份里网易云喜欢的时间：重装后账号列表还没同步。
        try store.restoreAccountTimes([FavoriteSong(track: track("netease", "a"), addedAt: now.addingTimeInterval(-7200)),
                                       FavoriteSong(track: track("netease", "b"), addedAt: now.addingTimeInterval(-10800))])
        // 平台列表不带时间；新喜欢的 c 在最前，d 备份里没有。
        store.register("netease", provider: FavoritesProvider(account: { "u" }, load: {
            [self.track("netease", "c"), self.track("netease", "a"), self.track("netease", "b"), self.track("netease", "d")]
        }, setLiked: { _, _ in }))
        await store.refresh("netease")
        #expect(store.songs.map(\.itemID) == ["c", "disc/1", "a", "b", "d"])
        #expect(store.songs.first { $0.itemID == "a" }?.addedAt == now.addingTimeInterval(-7200))

        // 再同步一次：已有时间保持不变。
        await store.refresh("netease")
        #expect(store.songs.map(\.itemID) == ["c", "disc/1", "a", "b", "d"])
        #expect(FavoritesStore(directory: folder).records["netease/u"]?.first { $0.itemID == "b" }?.addedAt == now.addingTimeInterval(-10800))
    }

    @Test func restoringTimesFixesListsAlreadySyncedAsNew() async throws {
        let folder = directory(); defer { try? FileManager.default.removeItem(at: folder) }
        let store = FavoritesStore(directory: folder)
        let old = Date.now.addingTimeInterval(-86400)
        let dizzy = Track(discID: "disc", number: "1", title: "Dizzy", artists: "", albumTitle: "", coverURL: nil)
        _ = try store.importDeviceSongs([FavoriteSong(track: dizzy, addedAt: Date.now.addingTimeInterval(-60))])
        store.register("netease", provider: FavoritesProvider(account: { "u" }, load: { [self.track("netease", "a")] }, setLiked: { _, _ in }))
        await store.refresh("netease")
        #expect(store.songs.first?.itemID == "a")
        // 导入备份：较早的真实时间替换同步时记下的「刚刚」，本机的喜欢回到前面。
        try store.restoreAccountTimes([FavoriteSong(track: track("netease", "a"), addedAt: old)])
        #expect(store.songs.map(\.itemID) == ["disc/1", "a"])
        // 备份时间更晚时不覆盖。
        try store.restoreAccountTimes([FavoriteSong(track: track("netease", "a"), addedAt: .now)])
        #expect(store.songs.last?.addedAt == old)
    }

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
        #expect(!store.contains(song))
        account = "a"; store.updateAccounts(); #expect(store.contains(song))
        account = nil; store.updateAccounts(); #expect(store.songs.isEmpty)
        #expect(!store.contains(song))
    }

    @Test func cachedFavoritesFollowDeviceProviderAvailabilityAndMutations() async throws {
        let folder = directory(); defer { try? FileManager.default.removeItem(at: folder) }
        let store = FavoritesStore(directory: folder)
        let local = Track(discID: "", number: "1", title: "Local", artists: "", albumTitle: "", coverURL: nil,
                          localSource: .init(albumID: "album", trackID: "local"))
        let other = track("extension", "1")
        store.registerDeviceProvider("extension")
        try await store.setLiked(local, true)
        try await store.setLiked(other, true)
        #expect(store.songs.map(\.id) == ["extension/1", "local/local"])
        #expect(store.contains(other))

        store.setDeviceProviders(["local"])
        #expect(!store.contains(other))
        #expect(store.songs.map(\.id) == ["local/local"])
        store.registerDeviceProvider("extension")
        #expect(store.contains(other))
        #expect(store.songs.map(\.id) == ["extension/1", "local/local"])
        try await store.setLiked(other, false)
        #expect(!store.contains(other))
        #expect(store.contains(local))
        #expect(store.songs.map(\.id) == ["local/local"])

        try await store.setLiked(other, true)
        #expect(store.contains(other))
        store.unregister("extension")
        #expect(!store.contains(other))
        #expect(store.songs.map(\.id) == ["local/local"])
        #expect(store.records["device"]?.count == 2)
    }

    @Test func cachedFavoriteReadsKeepObservationDependencies() async throws {
        let folder = directory(); defer { try? FileManager.default.removeItem(at: folder) }
        let store = FavoritesStore(directory: folder), song = track()
        var account: String? = "a"
        store.register("netease", provider: FavoritesProvider(account: { account }, load: { [song] }, setLiked: { _, _ in }))
        await store.refresh()
        #expect(store.contains(song)) // Populate the cache before observation starts.
        let accountChanges = Mutex(0)
        withObservationTracking {
            _ = store.contains(song)
        } onChange: {
            accountChanges.withLock { $0 += 1 }
        }
        account = nil
        store.updateAccounts()
        #expect(accountChanges.withLock { $0 } == 1)
        #expect(!store.contains(song))

        account = "a"
        store.updateAccounts()
        #expect(store.contains(song))
        let recordChanges = Mutex(0)
        withObservationTracking {
            _ = store.songs
        } onChange: {
            recordChanges.withLock { $0 += 1 }
        }
        try await store.setLiked(song, false)
        #expect(recordChanges.withLock { $0 } == 1)
        #expect(store.songs.isEmpty)
        #expect(!store.contains(song))

        let providerChanges = Mutex(0)
        withObservationTracking {
            _ = store.songs
        } onChange: {
            providerChanges.withLock { $0 += 1 }
        }
        store.setDeviceProviders(["local"])
        #expect(providerChanges.withLock { $0 } == 1)
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

    @Test func reenabledSameAccountRefreshRejectsOldProviderAndKeepsNewSyncMarker() async {
        let folder = directory(); defer { try? FileManager.default.removeItem(at: folder) }
        let store = FavoritesStore(directory: folder)
        var oldRead: CheckedContinuation<[Track], Never>?
        var newRead: CheckedContinuation<[Track], Never>?
        var oldLoads = 0
        store.register("netease", provider: FavoritesProvider(account: { "same" }, load: {
            oldLoads += 1
            return await withCheckedContinuation { oldRead = $0 }
        }, setLiked: { _, _ in }))
        let oldTask = Task { await store.refresh("netease") }
        while oldRead == nil { await Task.yield() }
        store.unregister("netease")
        store.register("netease", provider: FavoritesProvider(account: { "same" }, load: {
            await withCheckedContinuation { newRead = $0 }
        }, setLiked: { _, _ in }))
        let newTask = Task { await store.refresh("netease") }
        while newRead == nil { await Task.yield() }
        oldRead?.resume(returning: [track("netease", "old")])
        await oldTask.value
        #expect(store.syncing.contains("netease"))
        #expect(store.songs.isEmpty)
        #expect(oldLoads == 1)
        newRead?.resume(returning: [track("netease", "new")])
        await newTask.value
        #expect(store.songs.map(\.itemID) == ["new"])
        #expect(!store.syncing.contains("netease"))
    }

    @Test func reenabledSameAccountWriteRejectsOldCommitAndKeepsNewPendingMarker() async throws {
        let folder = directory(); defer { try? FileManager.default.removeItem(at: folder) }
        let store = FavoritesStore(directory: folder), song = track()
        var oldWrite: CheckedContinuation<Void, Never>?
        var newWrite: CheckedContinuation<Void, Never>?
        store.register("netease", provider: FavoritesProvider(account: { "same" }, load: { [] }, setLiked: { _, _ in
            await withCheckedContinuation { oldWrite = $0 }
        }))
        let oldTask = Task { try await store.setLiked(song, true) }
        while oldWrite == nil { await Task.yield() }
        store.unregister("netease")
        store.register("netease", provider: FavoritesProvider(account: { "same" }, load: { [] }, setLiked: { _, _ in
            await withCheckedContinuation { newWrite = $0 }
        }))
        let newTask = Task { try await store.setLiked(song, true) }
        while newWrite == nil { await Task.yield() }
        oldWrite?.resume()
        await #expect(throws: CancellationError.self) { try await oldTask.value }
        #expect(store.pending.contains(FavoriteSong(track: song).id))
        #expect(!store.contains(song))
        newWrite?.resume()
        try await newTask.value
        #expect(store.contains(song))
        #expect(store.pending.isEmpty)
    }

    @Test func slowProviderDoesNotBlockOtherFavoriteSync() async {
        let folder = directory(); defer { try? FileManager.default.removeItem(at: folder) }
        let store = FavoritesStore(directory: folder)
        var slow: CheckedContinuation<[Track], Never>?
        store.register("aaa", provider: FavoritesProvider(account: { "a" }, load: {
            await withCheckedContinuation { slow = $0 }
        }, setLiked: { _, _ in }))
        store.register("zzz", provider: FavoritesProvider(account: { "b" }, load: { [track("zzz", "ready")] }, setLiked: { _, _ in }))
        let work = Task { await store.refresh() }
        while slow == nil || !store.contains(track("zzz", "ready")) { await Task.yield() }
        #expect(store.contains(track("zzz", "ready")))
        slow?.resume(returning: [])
        await work.value
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
