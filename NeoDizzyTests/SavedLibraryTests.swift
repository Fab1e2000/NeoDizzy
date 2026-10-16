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

    @Test func accountItemsOnlyOfferRemovalWhenTheAccountAllowsIt() {
        func item(_ provider: String, _ kind: MirroredCollection.Kind, _ id: String, permanent: Bool = false, liked: Bool = false) -> MirroredCollection {
            MirroredCollection(providerID: provider, kind: kind, itemID: id, title: "标题", subtitle: "副标题", coverURL: nil,
                               isLikedPlaylist: liked, isPermanent: permanent, firstSeen: .now)
        }
        // 自建歌单与「我喜欢的音乐」只能在网易云里管理；收藏的歌单和专辑可以移除。
        #expect(LibraryShelfItem(mirrored: item("netease", .playlist, "1", permanent: true, liked: true))?.removal == nil)
        #expect(LibraryShelfItem(mirrored: item("netease", .playlist, "2"))?.removal == .neteasePlaylist(2))
        #expect(LibraryShelfItem(mirrored: item("netease", .album, "3"))?.removal == .neteaseAlbum(3))
        // DizzyLab 已购专辑不能移除。
        let purchased = LibraryShelfItem(mirrored: item("dizzylab", .album, "abc", permanent: true))
        #expect(purchased?.removal == nil)
        #expect(purchased?.origin == .dizzylab)
        // 网易云的 ID 必须是数字。
        #expect(LibraryShelfItem(mirrored: item("netease", .playlist, "x")) == nil)
        // 会改动账号的移除才需要确认。
        #expect(LibraryRemoval.saved("a").accountNotice == nil)
        #expect(LibraryRemoval.neteaseSong(1).accountNotice != nil)
    }
}

@MainActor
struct AccountLibraryMirrorTests {
    private func directory() -> URL {
        FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
    }

    private func purchases(_ id: String) -> Page<PurchasedDisc> {
        Page(items: [PurchasedDisc(disc: DiscSummary(id: id, title: id, coverURL: nil), purchaseDate: nil)], hasMore: false)
    }

    @Test func logoutDoesNotWaitForOrRestoreAnOldPurchaseRequest() async throws {
        let folder = directory()
        defer { try? FileManager.default.removeItem(at: folder) }
        var request: CheckedContinuation<Page<PurchasedDisc>, Never>?
        let mirror = AccountLibraryMirror(directory: folder, loadPurchases: { _, _ in
            await withCheckedContinuation { request = $0 }
        })
        let reading = Task { try await mirror.syncDizzyLab(userID: 1) }
        while request == nil { await Task.yield() }
        // Logout must finish before the suspended network request does.
        try await mirror.syncDizzyLab(userID: nil)
        #expect(mirror.dizzyLabAlbums.isEmpty)
        request?.resume(returning: purchases("old-account"))
        do { try await reading.value; Issue.record("Old account request should be cancelled") }
        catch is CancellationError { }
        #expect(mirror.dizzyLabAlbums.isEmpty)
        #expect(AccountLibraryMirror(directory: folder).dizzyLabAlbums.isEmpty)
    }

    @Test func switchingAccountsStartsANewRequestAndRejectsLateOldResults() async throws {
        let folder = directory()
        defer { try? FileManager.default.removeItem(at: folder) }
        var request: CheckedContinuation<Page<PurchasedDisc>, Never>?
        let mirror = AccountLibraryMirror(directory: folder, loadPurchases: { userID, _ in
            if userID == 1 { return await withCheckedContinuation { request = $0 } }
            return purchases("new-account")
        })
        let reading = Task { try await mirror.syncDizzyLab(userID: 1) }
        while request == nil { await Task.yield() }
        try await mirror.syncDizzyLab(userID: 2)
        #expect(mirror.dizzyLabAlbums.map(\.itemID) == ["new-account"])
        request?.resume(returning: purchases("old-account"))
        do { try await reading.value; Issue.record("Old account request should be cancelled") }
        catch is CancellationError { }
        #expect(mirror.dizzyLabAlbums.map(\.itemID) == ["new-account"])
        #expect(AccountLibraryMirror(directory: folder).dizzyLabAlbums.map(\.itemID) == ["new-account"])
    }

    @Test func failedNewAccountSyncClearsThePreviousAccountsPersistedAlbums() async throws {
        enum Failure: Error { case network }
        let folder = directory()
        defer { try? FileManager.default.removeItem(at: folder) }
        let mirror = AccountLibraryMirror(directory: folder, loadPurchases: { userID, _ in
            if userID == 2 { throw Failure.network }
            return purchases("old-account")
        })
        try await mirror.syncDizzyLab(userID: 1)
        #expect(mirror.dizzyLabAlbums.count == 1)
        await #expect(throws: Failure.self) { try await mirror.syncDizzyLab(userID: 2) }
        #expect(mirror.dizzyLabAlbums.isEmpty)
        #expect(AccountLibraryMirror(directory: folder).dizzyLabAlbums.isEmpty)
    }
}
