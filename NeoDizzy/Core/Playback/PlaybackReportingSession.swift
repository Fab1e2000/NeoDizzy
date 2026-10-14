import Foundation

/// Tracks audible playback, independently of queue position and seeking. Preparing
/// an AVPlayerItem never starts a listening record.
final class PlaybackReportingSession {
    var onStart: ((Track, Int?) -> Void)?
    var onFinish: ((Track, Int?, TimeInterval) -> Void)?
    private let now: () -> TimeInterval
    private var track: Track?
    private var sourceID: Int?
    private var started = false
    private var playingSince: TimeInterval?
    private var elapsed: TimeInterval = 0

    init(now: @escaping () -> TimeInterval = { ProcessInfo.processInfo.systemUptime }) { self.now = now }

    func begin(_ track: Track, sourceID: Int?) {
        finish()
        self.track = track
        self.sourceID = sourceID
    }
    func resumeIfNeeded(_ track: Track?, sourceID: Int?) {
        if self.track == nil, let track { begin(track, sourceID: sourceID) }
    }
    func setPlaying(_ playing: Bool) {
        let instant = now()
        if let since = playingSince { elapsed += max(0, instant - since) }
        playingSince = playing && track != nil ? instant : nil
        if playing, !started, let track {
            started = true
            onStart?(track, sourceID)
        }
    }
    func finish() {
        setPlaying(false)
        if started, let track {
            let duration = track.duration.flatMap { $0.isFinite && $0 > 0 ? $0 : nil }
            onFinish?(track, sourceID, min(elapsed, duration ?? elapsed))
        }
        track = nil; sourceID = nil; started = false; elapsed = 0
    }
}
