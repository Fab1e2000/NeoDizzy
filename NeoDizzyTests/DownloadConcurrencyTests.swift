import Foundation
import Testing
@testable import NeoDizzy

@MainActor struct DownloadConcurrencyTests {
    @Test func processingOverlapsSourcesAndLimitChangesApplyWithoutInterruptingWork() async throws {
        let fixture = try QueueFixture()
        defer { fixture.cleanup() }
        let store = fixture.store
        let provider = fixture.provider
        await store.restore()
        try await eventually { provider.processing && provider.started.count == 2 }
        #expect(store.jobs[0].transfers[0].state == .processing)
        store.concurrentDownloadCount = 3
        try await eventually { provider.started.count == 3 }
        store.concurrentDownloadCount = 1
        let started = provider.started
        provider.released.insert(started[0])
        try await eventually { provider.finished.count == 1 }
        #expect(provider.started.count == 3)
        provider.released.insert(started[1])
        try await eventually { provider.finished.count == 2 }
        #expect(provider.started.count == 3)
        provider.released.insert(started[2])
        try await eventually { provider.started.count == 4 }
        provider.released.insert(provider.started[3])
        try await eventually { provider.finished.count == 4 }
        #expect(store.jobs[0].isActive)
        #expect(!provider.completedCalled)
        provider.releaseProcessing = true
        try await eventually { store.jobs[0].state == .completed }
        #expect(provider.completedCalled)
        #expect(store.jobs[0].transfers.allSatisfy { $0.state == .completed })
        let reloaded = DownloadStore(library: fixture.library, directory: fixture.queue,
            transportIdentifier: "Reload.\(UUID())", defaults: fixture.defaults)
        #expect(reloaded.concurrentDownloadCount == 1)
        await store.remove(store.jobs[0])
    }

    @Test func removalCancelsBothLanesAndRemovesUnfinishedFiles() async throws {
        let fixture = try QueueFixture()
        defer { fixture.cleanup() }
        await fixture.store.restore()
        try await eventually { fixture.provider.processing && fixture.provider.started.count == 2 }
        await fixture.store.remove(fixture.store.jobs[0])
        #expect(fixture.store.jobs.isEmpty)
        #expect(fixture.provider.cancelledSources == 2)
        #expect(fixture.provider.cancelledProcessing)
        #expect(!fixture.provider.completedCalled)
        let remaining = try FileManager.default.contentsOfDirectory(atPath: fixture.queue.path)
        #expect(!remaining.contains { $0.hasSuffix(".zip") || $0.hasSuffix(".contents") })
    }

    @Test func concurrencyLimitIsSharedAcrossJobs() async throws {
        let fixture = try QueueFixture(jobCount: 2)
        defer { fixture.cleanup() }
        fixture.store.concurrentDownloadCount = 3
        await fixture.store.restore()
        try await eventually {
            fixture.provider.started.count == 3 &&
            fixture.store.jobs.allSatisfy { $0.transfers[0].state == .processing }
        }
        #expect(fixture.provider.started.count == 3)
        for job in fixture.store.jobs { await fixture.store.remove(job) }
        #expect(fixture.store.jobs.isEmpty)
    }

    @Test func disablingSourceCancelsOnlyItsWorkAndPreservesLibraryFiles() async throws {
        let fixture = try QueueFixture(jobCount: 2, separateProviders: true)
        defer { fixture.cleanup() }
        fixture.store.concurrentDownloadCount = 6
        let retained = fixture.root.appendingPathComponent("music/keep.flac")
        try FileManager.default.createDirectory(at: retained.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data("committed".utf8).write(to: retained)
        await fixture.store.restore()
        try await eventually {
            fixture.provider.processing && fixture.otherProvider.processing &&
            !fixture.provider.started.isEmpty && !fixture.otherProvider.started.isEmpty
        }
        await fixture.store.unregister(fixture.provider.id)
        #expect(fixture.provider.cancelledProcessing)
        #expect(fixture.provider.cancelledSources == fixture.provider.started.count)
        #expect(!fixture.provider.completedCalled)
        #expect(!fixture.otherProvider.cancelledProcessing)
        #expect(fixture.otherProvider.cancelledSources == 0)
        #expect(fixture.store.jobs.first(where: { $0.providerID == fixture.provider.id })?.state == .failed)
        #expect(fixture.store.jobs.first(where: { $0.providerID == fixture.otherProvider.id })?.isActive == true)
        #expect(try Data(contentsOf: retained) == Data("committed".utf8))
        for job in fixture.store.jobs { await fixture.store.remove(job) }
    }

    @Test func missingSourceDoesNotRunRestorationOrTransfers() async throws {
        let fixture = try QueueFixture(registerProviders: false)
        defer { fixture.cleanup() }
        await fixture.store.restore()
        #expect(fixture.store.jobs.allSatisfy { $0.state == .failed })
        #expect(fixture.provider.started.isEmpty)
        #expect(!fixture.provider.processing)
        for job in fixture.store.jobs { await fixture.store.remove(job) }
    }

    private func eventually(_ predicate: () -> Bool) async throws {
        for _ in 0..<300 {
            if predicate() { return }
            try await Task.sleep(for: .milliseconds(10))
        }
        throw DownloadFailure.interrupted
    }
}

@MainActor private struct QueueFixture {
    let root: URL
    let queue: URL
    let suite: String
    let defaults: UserDefaults
    let library: OfflineLibraryStore
    let store: DownloadStore
    let provider = GatedDownloadProvider()
    let otherProvider = GatedDownloadProvider(id: "other")
    init(jobCount: Int = 1, separateProviders: Bool = false, registerProviders: Bool = true) throws {
        root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        queue = root.appendingPathComponent("queue")
        suite = "Concurrency.\(UUID())"
        defaults = UserDefaults(suiteName: suite)!
        try FileManager.default.createDirectory(at: queue, withIntermediateDirectories: true)
        let data = try JSONEncoder().encode(DownloadRequest(title: "并行测试", identity: "test", coverURL: nil, payload: Data()))
        var jobs: [DownloadJob] = []
        for index in 0..<jobCount {
            var job = DownloadJob(id: UUID(), providerID: separateProviders && index > 0 ? otherProvider.id : provider.id, requestData: data)
            job.transfers = (0..<5).map { _ in DownloadTransfer(id: UUID(), metadata: Data()) }
            try Data("downloaded".utf8).write(to: queue.appendingPathComponent(job.transfers[0].id.uuidString + ".zip"))
            jobs.append(job)
        }
        try JSONEncoder().encode(DownloadSnapshot(version: 2, jobs: jobs)).write(to: queue.appendingPathComponent("jobs.json"))
        library = OfflineLibraryStore(defaults: defaults,
            scanner: LocalLibraryScanner(cacheURL: root.appendingPathComponent("cache")), libraryRoot: root.appendingPathComponent("music"))
        store = DownloadStore(library: library, directory: queue, transportIdentifier: suite, defaults: defaults)
        if registerProviders {
            store.register(provider)
            if separateProviders { store.register(otherProvider) }
        }
    }
    func cleanup() {
        defaults.removePersistentDomain(forName: suite)
        try? FileManager.default.removeItem(at: root)
    }
}

@MainActor private final class GatedDownloadProvider: DownloadProvider {
    let id: String
    init(id: String = "test") { self.id = id }
    var started: [UUID] = []
    var released = Set<UUID>()
    var finished = Set<UUID>()
    var processing = false
    var releaseProcessing = false
    var completedCalled = false
    var cancelledSources = 0
    var cancelledProcessing = false
    func title(_ request: Data) -> String { "测试" }
    func identity(_ request: Data) -> String { "test" }
    func plan(_ request: Data) async throws -> [DownloadTransfer] { [] }
    func source(_ transfer: DownloadTransfer) async throws -> DownloadSource? {
        started.append(transfer.id)
        do {
            while !released.contains(transfer.id) { try await Task.sleep(for: .milliseconds(10)) }
        } catch { cancelledSources += 1; throw error }
        finished.insert(transfer.id)
        return nil
    }
    func finalize(_ file: URL, metadata: Data, staging: URL) async throws -> PreparedDownload {
        processing = true
        do {
            while !releaseProcessing { try await Task.sleep(for: .milliseconds(10)) }
        } catch { cancelledProcessing = true; throw error }
        try Fixture.data("audio-local-tags.flac").write(to: staging.appendingPathComponent("01.flac"))
        let track = Track(discID: "1", number: "1", title: "测试", artists: "歌手", albumTitle: "测试专辑", coverURL: nil,
                          remoteSource: RemoteTrackSource(providerID: id, itemID: "1"))
        let manifest = LibraryManifest(source: LibrarySource(provider: id, kind: "album", id: "1"), title: "测试专辑", artist: "歌手",
                                       entries: [.init(relativePath: "01.flac", itemID: "1", track: track)])
        return PreparedDownload(folderName: "测试专辑", provenance: .collection(manifest, merge: true, preserving: [], placeholderMarker: nil))
    }
    func completed(_ request: Data, transfers: [DownloadTransfer]) async throws { completedCalled = true }
}
