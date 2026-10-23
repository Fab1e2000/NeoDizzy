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

@MainActor struct DownloadPersistenceTests {
    private final class Provider: DownloadProvider {
        let id = "test"
        var plans = 0
        func title(_ request: Data) -> String { "test" }
        func identity(_ request: Data) -> String { "test" }
        func plan(_ request: Data) async throws -> [DownloadTransfer] {
            plans += 1
            throw DownloadFailure.unavailable
        }
        func source(_ transfer: DownloadTransfer) async throws -> DownloadSource? { nil }
        func finalize(_ file: URL, metadata: Data, staging: URL) async throws -> PreparedDownload {
            throw DownloadFailure.unavailable
        }
    }

    @Test func failedQueueWriteBlocksWorkAndRetryRestoresDurability() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let suite = "PersistenceTest.\(UUID())"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let library = OfflineLibraryStore(defaults: defaults, libraryRoot: root.appendingPathComponent("music"))
        var fail = false
        let queue = root.appendingPathComponent("queue")
        let store = DownloadStore(library: library, directory: queue, transportIdentifier: suite,
                                  defaults: defaults, writeData: { data, url in
            if fail { throw CocoaError(.fileWriteOutOfSpace) }
            try data.write(to: url, options: .atomic)
        })
        let provider = Provider()
        store.register(provider)
        await store.restore()
        let previous = try Data(contentsOf: queue.appendingPathComponent("jobs.json"))
        fail = true
        await store.enqueue(providerID: provider.id, request: DownloadRequest(title: "test", identity: "test", coverURL: nil, payload: Data()))
        for _ in 0..<10 { await Task.yield() }
        #expect(provider.plans == 0)
        #expect(store.jobs.count == 1)
        #expect(store.jobs.first?.state == .queued)
        #expect(store.persistenceError != nil)
        #expect(try Data(contentsOf: queue.appendingPathComponent("jobs.json")) == previous)
        fail = false
        store.retryPersistence()
        #expect(store.persistenceError == nil)
        let snapshot = try JSONDecoder().decode(DownloadSnapshot.self, from: Data(contentsOf: queue.appendingPathComponent("jobs.json")))
        #expect(snapshot.jobs.map(\.id) == store.jobs.map(\.id))
        for _ in 0..<100 { if provider.plans > 0 { break }; await Task.yield() }
        #expect(provider.plans == 1)
    }
}
