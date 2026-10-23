import Foundation

/// A continuous QQ radio session owns its buffered songs and one prefetched batch.
/// Consumer ordering is independent of the fetch task, so cancellation and reset
/// cannot let two callers remove the same buffered song or revive an old batch.
@MainActor final class QQMusicRadioSession {
    private struct Batch {
        let id: UUID
        let task: Task<[Track], Error>
    }
    private struct Waiter {
        let id: UUID
        let continuation: CheckedContinuation<Void, Error>
    }

    private let fetch: @MainActor () async throws -> [Track]
    private var songs: [Track] = []
    private var pending: Batch?
    private var generation = 0
    private var consumer: UUID?
    private var waiters: [Waiter] = []
    private var recentIDs: [String] = []
    private var recentIDSet = Set<String>()

    init(fetch: @escaping @MainActor () async throws -> [Track]) { self.fetch = fetch }

    func reset() {
        generation += 1
        pending?.task.cancel(); pending = nil
        songs.removeAll(); recentIDs.removeAll(); recentIDSet.removeAll()
        consumer = nil
        let abandoned = waiters
        waiters.removeAll()
        abandoned.forEach { $0.continuation.resume(throwing: CancellationError()) }
    }

    func start(with initial: [Track] = []) async throws -> Track {
        try Task.checkCancellation()
        reset()
        songs = uniqueNewSongs(initial)
        return try await next()
    }

    func next() async throws -> Track {
        let revision = generation, id = UUID()
        return try await withTaskCancellationHandler {
            try await acquireConsumer(id, revision: revision)
            defer { releaseConsumer(id, revision: revision) }
            return try await takeNext(consumer: id, revision: revision)
        } onCancel: {
            Task { @MainActor [weak self] in self?.cancelConsumer(id, revision: revision) }
        }
    }

    private func takeNext(consumer id: UUID, revision: Int) async throws -> Track {
        // A server may repeat its radio batch. Retry only a small bounded number
        // of batches, then let the next user action retry instead of looping.
        var emptyBatches = 0
        while emptyBatches < 3 {
            try checkConsumer(id, revision: revision)
            if !songs.isEmpty {
                let track = songs.removeFirst()
                remember(track.id)
                if songs.count <= 1 { prefetch() }
                return track
            }
            let batch = prefetch()
            let tracks: [Track]
            do { tracks = try await batch.task.value }
            catch {
                guard revision == generation else { throw CancellationError() }
                if pending?.id == batch.id { pending = nil }
                try checkConsumer(id, revision: revision)
                throw error
            }
            try checkConsumer(id, revision: revision)
            guard pending?.id == batch.id else { continue }
            pending = nil
            songs = uniqueNewSongs(tracks)
            if songs.isEmpty { emptyBatches += 1 }
        }
        throw QQMusicError.unavailable
    }

    @discardableResult
    private func prefetch() -> Batch {
        if let pending { return pending }
        let fetch = fetch
        let batch = Batch(id: UUID(), task: Task { try await fetch() })
        pending = batch
        return batch
    }

    private func uniqueNewSongs(_ tracks: [Track]) -> [Track] {
        var seen = recentIDSet
        return tracks.filter { seen.insert($0.id).inserted }
    }

    private func remember(_ id: String) {
        recentIDs.append(id); recentIDSet.insert(id)
        // Bound memory while excluding overlaps across nearby recommendation batches.
        if recentIDs.count > 100 { recentIDSet.remove(recentIDs.removeFirst()) }
    }

    private func acquireConsumer(_ id: UUID, revision: Int) async throws {
        try Task.checkCancellation()
        guard revision == generation else { throw CancellationError() }
        if consumer == nil { consumer = id; return }
        try await withCheckedThrowingContinuation { waiters.append(Waiter(id: id, continuation: $0)) }
    }

    private func checkConsumer(_ id: UUID, revision: Int) throws {
        try Task.checkCancellation()
        guard revision == generation, consumer == id else { throw CancellationError() }
    }

    private func releaseConsumer(_ id: UUID, revision: Int) {
        guard revision == generation, consumer == id else { return }
        if waiters.isEmpty { consumer = nil }
        else {
            let next = waiters.removeFirst()
            consumer = next.id
            next.continuation.resume()
        }
    }

    private func cancelConsumer(_ id: UUID, revision: Int) {
        guard revision == generation else { return }
        if consumer == id { releaseConsumer(id, revision: revision) }
        else if let index = waiters.firstIndex(where: { $0.id == id }) {
            waiters.remove(at: index).continuation.resume(throwing: CancellationError())
        }
    }
}
