import Foundation
import Observation

/// Data adapter for the imported MeloX player. Local/imported lyrics retain
/// priority, with platform lyrics used only when no local lyrics are available.
@Observable final class NowPlayingLyricsModel {
    private(set) var lyrics: LocalLyrics?
    private(set) var error: String?
    private(set) var revision = 0
    private var currentTrackID: String?
    func load(track: Track, library: OfflineLibraryStore, player: PlayerStore) async {
        currentTrackID = track.id
        lyrics = nil; error = nil
        do {
            var result = try await LocalLyricsReader.shared.load(trackID: track.id,
                audioURL: library.localFile(for: track), access: library.access(for: track))
            if result.isEmpty, track.remoteSource != nil, let remote = try await player.remoteLyrics(for: track) { result = remote }
            try Task.checkCancellation()
            lyrics = result
        } catch is CancellationError { }
        catch { if !Task.isCancelled { self.error = error.localizedDescription } }
    }
    func importFile(_ url: URL, trackID: String) async {
        do {
            try await LocalLyricsReader.shared.importFile(url, trackID: trackID)
            if currentTrackID == trackID { revision += 1 }
        }
        catch { if currentTrackID == trackID { self.error = error.localizedDescription } }
    }
}
