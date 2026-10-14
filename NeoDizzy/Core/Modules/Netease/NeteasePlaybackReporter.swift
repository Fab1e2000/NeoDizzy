import Foundation
import OSLog

/// Serial submission, no automatic write retries, and an account guard for both
/// queued requests and a song that spans logout/login. Mirrors MeloX's recorder.
final class NeteasePlaybackReporter {
    private let api: NeteaseAPI
    private var task: Task<Void, Never>?
    private var activeCookie: String?
    private var generation = 0
    private static let logger = Logger(subsystem: "com.elsterlee.NeoDizzy", category: "NeteasePlayback")
    init(api: NeteaseAPI) { self.api = api }
    func reset() { generation += 1; activeCookie = nil }
    func started(_ track: Track, sourceID: Int?) {
        activeCookie = nil
        guard track.remoteSource?.providerID == "netease",
              NeteaseClient.cookieValues(api.client.cookie)["MUSIC_U"] != nil else { return }
        activeCookie = api.client.cookie
        enqueue(track, sourceID: sourceID, seconds: nil)
    }
    func finished(_ track: Track, sourceID: Int?, seconds: TimeInterval) {
        defer { activeCookie = nil }
        guard seconds.isFinite, seconds >= 1 else { return }
        enqueue(track, sourceID: sourceID, seconds: Int(min(seconds, Double(Int32.max))))
    }
    private func enqueue(_ track: Track, sourceID: Int?, seconds: Int?) {
        guard track.remoteSource?.providerID == "netease", let id = Int(track.remoteSource?.itemID ?? ""),
              let cookie = activeCookie, cookie == api.client.cookie else { return }
        let previous = task, revision = generation, api = api
        let source = sourceID ?? Int(track.discID) ?? 0
        task = Task { [weak self] in
            await previous?.value
            guard let self, self.generation == revision, api.client.cookie == cookie else { return }
            do { try await api.reportPlayback(songID: id, sourceID: source, seconds: seconds) }
            catch is CancellationError { }
            catch { Self.logger.error("Playback report failed: \(error.localizedDescription, privacy: .private)") }
        }
    }
    func waitForPendingReports() async { await task?.value }
}
