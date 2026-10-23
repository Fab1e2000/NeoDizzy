import Foundation
import SwiftUI
import Testing
@testable import NeoDizzy

@MainActor struct DizzyLabMirrorRegistrationTests {
    private func item(_ provider: String) -> MirroredCollection {
        .init(providerID: provider, kind: .album, itemID: "1", title: provider, subtitle: "", coverURL: nil, firstSeen: .now)
    }
    @Test func builtInAdaptersReconcileSignedOutAccountsAtRegistration() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let mirror = AccountLibraryMirror(directory: directory)
        try await mirror.sync("dizzylab", account: "7") { commit in try commit([item("dizzylab")]) }
        // Injecting the API prevents reading any real keychain session.
        mirror.registerDizzyLab(account: { nil })
        #expect(mirror.collections.isEmpty)
        #expect(mirror.state("dizzylab").account == nil)
    }
}
