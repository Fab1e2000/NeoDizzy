import Foundation
import Testing
@testable import NeoDizzy

@MainActor struct PlaybackReportingTests {
    @Test func ignoresPreparationPausesAndDuplicateFinish() {
        var time: TimeInterval = 0
        let session = PlaybackReportingSession(now: { time })
        let track = Track(discID: "7", number: "1", title: "Song", artists: "", albumTitle: "", coverURL: nil, duration: 180)
        var starts = 0, durations: [Double] = []
        session.onStart = { _, source in #expect(source == 8); starts += 1 }
        session.onFinish = { _, _, seconds in durations.append(seconds) }
        session.begin(track, sourceID: 8)
        time = 30 // Prepared item has not played.
        #expect(starts == 0)
        session.setPlaying(true)
        time = 35; session.setPlaying(false)
        time = 100; session.setPlaying(true) // Pause/buffering is excluded.
        time = 107; session.finish(); session.finish()
        #expect(starts == 1)
        #expect(durations == [12])
        session.begin(track, sourceID: 8); session.finish()
        #expect(starts == 1 && durations == [12])
    }
    @Test func replacingAndRepeatingSongsCreatesDistinctSessions() {
        var time: TimeInterval = 0
        let session = PlaybackReportingSession(now: { time })
        let track = Track(discID: "7", number: "1", title: "Song", artists: "", albumTitle: "", coverURL: nil)
        var starts = 0, finishes = 0
        session.onStart = { _, _ in starts += 1 }
        session.onFinish = { _, _, _ in finishes += 1 }
        session.begin(track, sourceID: nil); session.setPlaying(true)
        time = 2
        session.begin(track, sourceID: nil); session.setPlaying(true)
        time = 4; session.finish()
        #expect(starts == 2 && finishes == 2)
    }
    @Test func qualityPreferencesPersistIndependentlyAndFollowNetwork() throws {
        let name = "NeteaseQuality.\(UUID())"
        let defaults = try #require(UserDefaults(suiteName: name))
        defer { defaults.removePersistentDomain(forName: name) }
        let settings = NeteasePlaybackSettings(defaults: defaults, monitorsNetwork: false)
        #expect(settings.wifi == .high && settings.cellular == .high)
        settings.wifi = .master; settings.cellular = .standard
        #expect(settings.selected == .master)
        settings.updateNetwork(isCellular: true)
        #expect(settings.selected == .standard)
        let restored = NeteasePlaybackSettings(defaults: defaults, monitorsNetwork: false)
        #expect(restored.wifi == .master && restored.cellular == .standard)
    }
}
