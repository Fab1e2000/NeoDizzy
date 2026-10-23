import Foundation
import SwiftUI
import Testing
@testable import NeoDizzy

@MainActor struct NeteaseMirrorRegistrationTests {
    private func item(_ provider: String) -> MirroredCollection {
        .init(providerID: provider, kind: .album, itemID: "1", title: provider, subtitle: "", coverURL: nil, firstSeen: .now)
    }
    @Test func builtInAdaptersReconcileSignedOutAccountsAtRegistration() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let mirror = AccountLibraryMirror(directory: directory)
        try await mirror.sync("netease", account: "42") { commit in try commit([item("netease")]) }
        // Injecting the API prevents reading any real keychain session.
        let store = NeteaseStore(api: NeteaseAPI(client: NeteaseClient()))
        mirror.registerNetease(store)
        #expect(mirror.collections.isEmpty)
        #expect(mirror.state("netease").account == nil)
    }
}
