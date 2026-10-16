import Foundation

/// FM batches belong to a playback session, not a three-song playlist screen.
final class NeteaseRadioSession {
    private var songs: [Track] = []
    private var pending: Task<[Track], Error>?
    private var generation = 0
    private let fetch: () async throws -> [Track]
    init(fetch: @escaping () async throws -> [Track]) { self.fetch = fetch }

    func reset() {
        generation += 1
        pending?.cancel(); pending = nil; songs = []
    }
    func start(with initial: [Track]) async throws -> Track {
        reset()
        songs = initial
        return try await next()
    }
    func next() async throws -> Track {
        let revision = generation
        if songs.isEmpty {
            prefetch()
            guard let pending else { throw NeteaseError.unavailable }
            let batch: [Track]
            do { batch = try await pending.value }
            catch {
                if revision == generation { self.pending = nil }
                throw error
            }
            try Task.checkCancellation()
            guard revision == generation else { throw CancellationError() }
            self.pending = nil
            guard !batch.isEmpty else { throw NeteaseError.unavailable }
            songs = batch
        }
        let track = songs.removeFirst()
        if songs.count <= 1 { prefetch() }
        return track
    }
    private func prefetch() {
        guard pending == nil else { return }
        pending = Task { try await fetch() }
    }
}
