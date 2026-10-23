import Foundation
import Testing
@testable import NeoDizzy

@MainActor struct LibraryProviderIsolationTests {
    private func item(_ provider: String) -> MirroredCollection {
        .init(providerID: provider, kind: .album, itemID: "1", title: provider, subtitle: "", coverURL: nil, firstSeen: .now)
    }
    @Test func registrationReconcilesAccountBeforeExposingCachedCollections() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let mirror = AccountLibraryMirror(directory: directory)
        try await mirror.sync("one", account: "old") { commit in try commit([item("one")]) }
        try await mirror.sync("two", account: "other") { commit in try commit([item("two")]) }
        var account: String? = "old"
        mirror.register("one", account: { account }) { _ in }
        mirror.register("two", account: { "other" }) { _ in }
        #expect(mirror.collections.count == 2) // Same-account re-enable preserves its cache.
        account = "new"
        #expect(mirror.collections.map(\.providerID) == ["two"]) // Hidden before async sync starts.
        mirror.unregister("one")
        mirror.register("one", account: { account }) { _ in }
        #expect(mirror.state("one").account == "new")
        #expect(mirror.state("one").collections.isEmpty)
        #expect(mirror.collections.map(\.providerID) == ["two"])
        let reloaded = AccountLibraryMirror(directory: directory)
        reloaded.register("two", account: { nil }) { _ in }
        #expect(reloaded.collections.isEmpty) // Signed-out startup cannot expose a previous account.
        #expect(reloaded.state("two").account == nil)
    }



    @Test func legacyMirrorMigratesWithoutLosingCollectionsOrFavoriteMetadata() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        struct Legacy: Encodable {
            var neteaseUserID = 42
            var likedTracks: [Int: Track] = [:]
            var likedOrder: [Int] = []
            var neteaseCollections: [MirroredCollection]
            var dizzyLabUserID = 7
            var dizzyLabAlbums: [MirroredCollection]
            var firstSeen: [String: Date] = [:]
            var artistIDs = ["Artist": 99]
            var artistAvatars: [Int: URL] = [:]
        }
        let old = Legacy(neteaseCollections: [item("netease")], dizzyLabAlbums: [item("dizzylab")])
        try JSONEncoder().encode(old).write(to: directory.appendingPathComponent("account-mirror.json"))
        let mirror = AccountLibraryMirror(directory: directory)
        #expect(mirror.state("netease").account == "42")
        #expect(mirror.state("dizzylab").account == "7")
        #expect(mirror.state("netease").artistIDs["Artist"] == "99")
        mirror.register("netease") { _ in }
        #expect(mirror.collections.map(\.providerID) == ["netease"])
        mirror.save()
        let reopened = AccountLibraryMirror(directory: directory)
        #expect(reopened.state("dizzylab").collections.count == 1)
    }
    @Test func disablingOneMirrorRetainsOtherProviderAndPersistedData() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let mirror = AccountLibraryMirror(directory: directory)
        mirror.register("one") { _ in }
        mirror.register("two") { _ in }
        try await mirror.sync("one", account: "account") { commit in try commit([item("one")]) }
        try await mirror.sync("two", account: "account") { commit in try commit([item("two")]) }
        mirror.unregister("one")
        #expect(mirror.collections.map(\.providerID) == ["two"])
        let restored = AccountLibraryMirror(directory: directory)
        #expect(restored.collections.isEmpty)
        restored.register("one") { _ in }
        #expect(restored.collections.map(\.providerID) == ["one"])
    }
    @Test func disablingMirrorRejectsLateResponseWithoutAffectingOtherAccount() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let mirror = AccountLibraryMirror(directory: directory)
        var continuation: CheckedContinuation<Void, Never>?
        mirror.register("one") { _ in }
        mirror.register("two") { _ in }
        let work = Task {
            try await mirror.sync("one", account: "a") { commit in
                await withCheckedContinuation { continuation = $0 }
                try commit([item("one")])
            }
        }
        while continuation == nil { await Task.yield() }
        mirror.unregister("one")
        try await mirror.sync("two", account: "b") { commit in try commit([item("two")]) }
        continuation?.resume()
        await #expect(throws: CancellationError.self) { try await work.value }
        #expect(mirror.collections.map(\.providerID) == ["two"])
        #expect(mirror.state("one").collections.isEmpty)
    }
    @Test func absentProviderDoesNotFallbackAndExportKeepsIncompleteCollection() async throws {
        let registry = LibraryProviderRegistry()
        var requests = 0
        registry.register("available", provider: .init(title: "Available", onlineSongs: { _ in requests += 1; return [] }))
        var export = LibraryExport(exportedAt: .now, favorites: [], savedSongs: [], collections: [
            .init(providerID: "missing", kind: "album", itemID: "1", title: "Missing", subtitle: "", songs: [], songsComplete: false),
            .init(providerID: "available", kind: "album", itemID: "1", title: "Available", subtitle: "", songs: [], songsComplete: false)
        ])
        try await export.loadOnlineSongs(providers: registry) { _, _ in }
        #expect(requests == 1)
        #expect(!export.collections[0].songsComplete)
        #expect(export.collections[0].issue != nil)
        #expect(export.collections[1].songsComplete)
    }
    @Test func disablingProviderRejectsAnInFlightExport() async throws {
        let registry = LibraryProviderRegistry()
        var continuation: CheckedContinuation<[Track], Never>?
        registry.register("one", provider: .init(title: "One", onlineSongs: { _ in
            await withCheckedContinuation { continuation = $0 }
        }))
        let item = LibraryExport.Collection(providerID: "one", kind: "album", itemID: "1", title: "One",
                                            subtitle: "", songs: [], songsComplete: false)
        let work = Task { try await registry.onlineSongs(item) }
        while continuation == nil { await Task.yield() }
        registry.unregister("one")
        continuation?.resume(returning: [])
        await #expect(throws: CancellationError.self) { try await work.value }
    }
    @Test func settingsAndCredentialsOnlyVisitRegisteredProviders() async {
        let registry = LibraryProviderRegistry()
        var applied: [String: String] = [:]
        registry.register("one", provider: .init(title: "One", exportSettings: { ["quality": "high"] },
                                               applySettings: { applied = $0 }, exportCredential: { "one-session" },
                                               restoreCredential: { _ in .restored }))
        registry.apply(["missing": ["quality": "wrong"], "one": ["quality": "lossless"]])
        #expect(applied == ["quality": "lossless"])
        #expect(registry.credentials() == ["one": "one-session"])
        let restored = await registry.restore(["one": "session", "missing": "session"])
        #expect(restored.keys.sorted() == ["one"])
        registry.unregister("one")
        #expect(registry.settings().isEmpty && registry.credentials().isEmpty)
    }
}
