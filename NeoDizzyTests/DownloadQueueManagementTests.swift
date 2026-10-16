import Foundation
import Testing
@testable import NeoDizzy

@MainActor struct DownloadQueueManagementTests {
    @Test func cancelAndRemovePersistWithoutDeletingLibraryAudio() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let queue = root.appendingPathComponent("queue")
        let music = root.appendingPathComponent("music")
        try FileManager.default.createDirectory(at: queue, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: music, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let audio = music.appendingPathComponent("keep.flac")
        try Data("saved audio".utf8).write(to: audio)
        let data = try JSONEncoder().encode(DownloadRequest(title: "测试任务", identity: "test", coverURL: nil, payload: Data()))
        var active = DownloadJob(id: UUID(), providerID: "test", requestData: data)
        active.state = .downloading
        active.transfers = [.init(id: UUID(), metadata: Data(), state: .downloaded)]
        var done = DownloadJob(id: UUID(), providerID: "test", requestData: data)
        done.state = .completed
        try JSONEncoder().encode(DownloadSnapshot(version: 2, jobs: [active, done])).write(to: queue.appendingPathComponent("jobs.json"))
        let suite = "QueueTest.\(UUID())"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let transfer = try #require(active.transfers.first)
        let archive = queue.appendingPathComponent(transfer.id.uuidString + ".zip")
        let staging = queue.appendingPathComponent(transfer.id.uuidString + ".contents")
        try Data("temporary".utf8).write(to: archive)
        try FileManager.default.createDirectory(at: staging, withIntermediateDirectories: true)
        let library = OfflineLibraryStore(defaults: defaults, libraryRoot: music)
        let store = DownloadStore(library: library, directory: queue, transportIdentifier: "QueueTest.\(UUID())")
        store.cancel(active)
        #expect(store.jobs.first?.state == .cancelled)
        await store.remove(active)
        #expect(store.jobs.map(\.id) == [done.id])
        #expect(!FileManager.default.fileExists(atPath: archive.path))
        #expect(!FileManager.default.fileExists(atPath: staging.path))
        await store.remove(done)
        #expect(store.jobs.isEmpty)
        let saved = try JSONDecoder().decode(DownloadSnapshot.self, from: Data(contentsOf: queue.appendingPathComponent("jobs.json")))
        #expect(saved.jobs.isEmpty)
        #expect(try Data(contentsOf: audio) == Data("saved audio".utf8))
    }
}
