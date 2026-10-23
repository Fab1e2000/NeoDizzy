import Foundation
import Observation

/// Data adapter for the imported MeloX player. Local/imported lyrics retain
/// priority, with platform lyrics used only when no local lyrics are available.
@Observable final class NowPlayingLyricsModel {
    private(set) var lyrics: LocalLyrics?
    private(set) var error: String?
    private(set) var revision = 0
    enum Availability: Equatable {
        case loading, available, unavailable
    }

    private var currentTrackID: String?
    private var loadGeneration = 0
    private var availability: Availability = .loading
    private let reader: LocalLyricsReader

    init(reader: LocalLyricsReader = .shared) {
        self.reader = reader
    }

    func availability(for trackID: String?) -> Availability {
        guard let trackID, currentTrackID == trackID else { return .loading }
        return availability
    }

    func load(track: Track, library: OfflineLibraryStore, player: PlayerStore) async {
        await load(trackID: track.id) {
            var result = try await self.reader.load(trackID: track.id,
                audioURL: library.localFile(for: track), access: library.access(for: track))
            if result.isEmpty, track.remoteSource != nil, let remote = try await player.remoteLyrics(for: track) { result = remote }
            return result
        }
    }

    /// Generation checks also reject stale results from uncancellable providers
    /// and overlapping reloads of the same track after a lyrics import.
    func load(trackID: String, resolve: () async throws -> LocalLyrics) async {
        loadGeneration += 1
        let generation = loadGeneration
        currentTrackID = trackID
        availability = .loading
        lyrics = nil
        error = nil
        do {
            let result = try await resolve()
            try Task.checkCancellation()
            guard generation == loadGeneration else { return }
            lyrics = result
            let hasText = !result.plainText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                || result.lines.contains { !$0.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
            availability = hasText ? .available : .unavailable
        } catch is CancellationError { }
        catch {
            guard !Task.isCancelled, generation == loadGeneration else { return }
            self.error = error.localizedDescription
            availability = .unavailable
        }
    }
    func importFile(_ url: URL, trackID: String) async {
        do {
            try await reader.importFile(url, trackID: trackID)
            if currentTrackID == trackID { revision += 1 }
        }
        catch { if currentTrackID == trackID { self.error = error.localizedDescription } }
    }
}
