import Foundation
import SwiftUI
import Testing
@testable import NeoDizzy

 struct DizzyLabDownloadMigrationTests {
    @Test func migratesActiveArchiveWithoutChangingBackgroundTaskIdentity() throws {
        let id = UUID()
        let detail = DiscDetail(summary: DiscSummary(id: "disc", title: "专辑", coverURL: nil), releaseDate: nil,
                                description: "", credits: "", labelDescription: "", hasGift: false, tracks: [], streams: [:])
        let album = try JSONSerialization.jsonObject(with: JSONEncoder().encode(DownloadAlbum(detail)))
        let data = try JSONSerialization.data(withJSONObject: [["id": id.uuidString, "album": album, "format": "FLAC", "state": "downloading"]])
        let migrated = try #require(DizzyLabDownloadProvider.migrate(data)?.first)
        #expect(migrated.id == id)
        #expect(migrated.transfers.first?.id == id)
        #expect(migrated.providerID == "dizzylab")
        #expect(migrated.discID == "disc")
        let snapshot = DownloadSnapshot(version: 2, jobs: [migrated])
        let restored = try JSONDecoder().decode(DownloadSnapshot.self, from: JSONEncoder().encode(snapshot))
        #expect(restored.jobs.first?.transfers.first?.id == id)
    }
}
