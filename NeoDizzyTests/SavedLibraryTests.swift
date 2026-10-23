import Foundation
import SwiftUI
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

    private final class CollectionModule: AppModule {
        let descriptor: ModuleDescriptor
        let requiresNumericID: Bool
        init(_ provider: String, numeric: Bool = false) {
            descriptor = ModuleDescriptor(id: ModuleID(rawValue: provider), title: provider, systemImage: "square")
            requiresNumericID = numeric
        }
        func rootView() -> AnyView { AnyView(EmptyView()) }
        func destination(for route: AppRoute) -> AnyView? { nil }
        func collectionRoute(kind: String, itemID: String) -> AppRoute? {
            guard ["album", "playlist"].contains(kind), !requiresNumericID || Int(itemID) != nil else { return nil }
            return AppRoute(moduleID: descriptor.id, destination: "\(kind)/\(itemID)", title: itemID)
        }
        func collectionRemoval(for item: MirroredCollection) -> LibraryRemoval? {
            guard !item.isPermanent, requiresNumericID, collectionRoute(kind: item.kind.rawValue, itemID: item.itemID) != nil else { return nil }
            return .account(providerID: item.providerID, kind: item.kind.rawValue, itemID: item.itemID, notice: "账号也会取消收藏此内容。")
        }
    }
    @Test func accountItemsOnlyOfferRemovalWhenTheAccountAllowsIt() throws {
        let modules = try ModuleRegistry([CollectionModule("account-fixture", numeric: true), CollectionModule("purchased-fixture")])
        func item(_ provider: String, _ kind: MirroredCollection.Kind, _ id: String, permanent: Bool = false, liked: Bool = false) -> MirroredCollection {
            MirroredCollection(providerID: provider, kind: kind, itemID: id, title: "标题", subtitle: "副标题", coverURL: nil,
                               isLikedPlaylist: liked, isPermanent: permanent, firstSeen: .now)
        }
        // The provider owns collection removal policy.
        #expect(LibraryShelfItem(mirrored: item("account-fixture", .playlist, "1", permanent: true, liked: true), modules: modules)?.removal == nil)
        #expect(LibraryShelfItem(mirrored: item("account-fixture", .playlist, "2"), modules: modules)?.removal == .account(providerID: "account-fixture", kind: "playlist", itemID: "2", notice: "账号也会取消收藏此内容。"))
        #expect(LibraryShelfItem(mirrored: item("account-fixture", .album, "3"), modules: modules)?.removal == .account(providerID: "account-fixture", kind: "album", itemID: "3", notice: "账号也会取消收藏此内容。"))
        // Permanent purchases cannot be removed.
        let purchased = LibraryShelfItem(mirrored: item("purchased-fixture", .album, "abc", permanent: true), modules: modules)
        #expect(purchased?.removal == nil)
        #expect(purchased?.origin.rawValue == "purchased-fixture")
        // The fixture provider rejects malformed IDs.
        #expect(LibraryShelfItem(mirrored: item("account-fixture", .playlist, "x"), modules: modules) == nil)
        // 会改动账号的移除才需要确认。
        modules.remove(ModuleID(rawValue: "account-fixture"))
        #expect(LibraryShelfItem(mirrored: item("account-fixture", .album, "3"), modules: modules) == nil)
        #expect(LibraryShelfItem(mirrored: item("purchased-fixture", .album, "abc", permanent: true), modules: modules) != nil)
        #expect(LibraryRemoval.saved("a").accountNotice == nil)
        #expect(LibraryRemoval.account(providerID: "test", kind: "album", itemID: "1", notice: "取消账号收藏").accountNotice != nil)
    }
}

@MainActor
struct AccountLibraryMirrorTests {
    private func directory() -> URL {
        FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
    }

    private func purchases(_ id: String) -> [MirroredCollection] {
        [.init(providerID: "fixture", kind: .album, itemID: id, title: id, subtitle: "", coverURL: nil, firstSeen: .now)]
    }
    private func sync(_ mirror: AccountLibraryMirror, account: Int?, load: @escaping (Int) async throws -> [MirroredCollection]) async throws {
        try await mirror.sync("fixture", account: account.map(String.init)) { commit in
            guard let account else { return }
            try commit(await load(account))
        }
    }

    @Test func logoutDoesNotWaitForOrRestoreAnOldPurchaseRequest() async throws {
        let folder = directory()
        defer { try? FileManager.default.removeItem(at: folder) }
        var request: CheckedContinuation<[MirroredCollection], Never>?
        let mirror = AccountLibraryMirror(directory: folder)
        let load: (Int) async -> [MirroredCollection] = { _ in await withCheckedContinuation { request = $0 } }
        let reading = Task { try await sync(mirror, account: 1, load: load) }
        while request == nil { await Task.yield() }
        // Logout must finish before the suspended network request does.
        try await sync(mirror, account: nil, load: load)
        #expect(mirror.state("fixture").collections.isEmpty)
        request?.resume(returning: purchases("old-account"))
        do { try await reading.value; Issue.record("Old account request should be cancelled") }
        catch is CancellationError { }
        #expect(mirror.state("fixture").collections.isEmpty)
        #expect(AccountLibraryMirror(directory: folder).state("fixture").collections.isEmpty)
    }

    @Test func switchingAccountsStartsANewRequestAndRejectsLateOldResults() async throws {
        let folder = directory()
        defer { try? FileManager.default.removeItem(at: folder) }
        var request: CheckedContinuation<[MirroredCollection], Never>?
        let mirror = AccountLibraryMirror(directory: folder)
        let load: (Int) async -> [MirroredCollection] = { userID in
            if userID == 1 { return await withCheckedContinuation { request = $0 } }
            return purchases("new-account")
        }
        let reading = Task { try await sync(mirror, account: 1, load: load) }
        while request == nil { await Task.yield() }
        try await sync(mirror, account: 2, load: load)
        #expect(mirror.state("fixture").collections.map(\.itemID) == ["new-account"])
        request?.resume(returning: purchases("old-account"))
        do { try await reading.value; Issue.record("Old account request should be cancelled") }
        catch is CancellationError { }
        #expect(mirror.state("fixture").collections.map(\.itemID) == ["new-account"])
        #expect(AccountLibraryMirror(directory: folder).state("fixture").collections.map(\.itemID) == ["new-account"])
    }

    @Test func failedNewAccountSyncClearsThePreviousAccountsPersistedAlbums() async throws {
        enum Failure: Error { case network }
        let folder = directory()
        defer { try? FileManager.default.removeItem(at: folder) }
        let mirror = AccountLibraryMirror(directory: folder)
        let load: (Int) async throws -> [MirroredCollection] = { userID in
            if userID == 2 { throw Failure.network }
            return purchases("old-account")
        }
        try await sync(mirror, account: 1, load: load)
        #expect(mirror.state("fixture").collections.count == 1)
        await #expect(throws: Failure.self) { try await sync(mirror, account: 2, load: load) }
        #expect(mirror.state("fixture").collections.isEmpty)
        #expect(AccountLibraryMirror(directory: folder).state("fixture").collections.isEmpty)
    }
}

@MainActor struct SavedLibraryPersistenceTests {
    @Test func failedAddAndRemoveKeepPublishedAndDurableStateUntilRetry() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        var fail = true
        let store = SavedLibraryStore(directory: directory, writeData: { data, url in
            if fail { throw CocoaError(.fileWriteOutOfSpace) }
            try data.write(to: url, options: .atomic)
        })
        let item = SavedLibraryItem(kind: .album, providerID: "test", itemID: "1",
                                   title: "Album", subtitle: "", coverURL: nil, addedAt: .now)
        #expect(!store.add(item))
        #expect(store.items.isEmpty)
        #expect(store.persistenceError != nil)
        #expect(SavedLibraryStore(directory: directory).items.isEmpty)
        fail = false
        #expect(store.retryPersistence())
        #expect(store.persistenceError == nil)
        #expect(SavedLibraryStore(directory: directory).items == [item])
        fail = true
        #expect(!store.remove(id: item.id))
        #expect(store.items == [item])
        #expect(SavedLibraryStore(directory: directory).items == [item])
        fail = false
        #expect(store.retryPersistence())
        #expect(store.persistenceError == nil)
        #expect(SavedLibraryStore(directory: directory).items.isEmpty)
    }
}
