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
    @Test func unifiedQualityMigratesAndPersists() throws {
        let name = "NeteaseQuality.\(UUID())"
        let defaults = try #require(UserDefaults(suiteName: name))
        defer { defaults.removePersistentDomain(forName: name) }
        defaults.set("hires", forKey: "netease.quality.wifi")
        defaults.set("standard", forKey: "netease.quality.download")
        let settings = NeteasePlaybackSettings(defaults: defaults)
        #expect(settings.quality == .hiResolution)
        var changes = 0
        settings.changed = { changes += 1 }
        settings.quality = .master
        settings.quality = .master
        #expect(changes == 1)
        #expect(settings.selected == .master)
        #expect(NeteasePlaybackSettings(defaults: defaults).quality == .master)
    }
}
