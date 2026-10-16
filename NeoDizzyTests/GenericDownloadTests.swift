import Foundation
import Testing
@testable import NeoDizzy

struct GenericDownloadTests {
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

    @Test func mergeAddsOnlyNewEntriesAndRejectsUnrelatedCollections() throws {
        let fm = FileManager.default
        let root = fm.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let staging = root.appendingPathComponent("staging")
        let library = root.appendingPathComponent("library")
        try fm.createDirectory(at: staging, withIntermediateDirectories: true)
        try fm.createDirectory(at: library, withIntermediateDirectories: true)
        defer { try? fm.removeItem(at: root) }
        func manifest(_ id: String, album: String = "album") throws -> LibraryManifest {
            try Data(id.utf8).write(to: staging.appendingPathComponent("\(id).wav"))
            let track = Track(discID: album, number: id, title: id, artists: "歌手", albumTitle: "专辑", coverURL: nil,
                              remoteSource: .init(providerID: "test", itemID: id))
            return LibraryManifest(source: .init(provider: "test", kind: "album", id: album), title: "专辑", artist: "歌手",
                                   entries: [.init(relativePath: "\(id).wav", itemID: id, track: track)])
        }
        let first = try manifest("1")
        _ = try OfflineLibraryWorker.commitDirectory(staging: staging, folderName: "专辑", provenance: .collection(first, merge: true, preserving: [], placeholderMarker: nil), into: library)
        try fm.removeItem(at: staging.appendingPathComponent("1.wav"))
        let second = try manifest("2")
        let result = try OfflineLibraryWorker.commitDirectory(staging: staging, folderName: "专辑", provenance: .collection(second, merge: true, preserving: [], placeholderMarker: nil), into: library)
        #expect(result?.manifest.entries.map(\.itemID) == ["1", "2"])
        #expect(try Data(contentsOf: library.appendingPathComponent("专辑/1.wav")) == Data("1".utf8))
        let other = try manifest("3", album: "other")
        #expect(throws: OfflineLibraryError.existingAlbum) {
            try OfflineLibraryWorker.commitDirectory(staging: staging, folderName: "专辑", provenance: .collection(other, merge: true, preserving: [], placeholderMarker: nil), into: library)
        }
    }
}
