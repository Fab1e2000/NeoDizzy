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

}

@MainActor struct PlaybackReportingIsolationTests {
    @Test func unregisterOnlyRemovesThatSourcesReporter() {
        let reporting = PlaybackReportingSession()
        var first = 0, second = 0, history = 0
        reporting.onStart = { _, _ in history += 1 }
        reporting.register("first", onStart: { _, _ in first += 1 }, onFinish: { _, _, _ in })
        reporting.register("second", onStart: { _, _ in second += 1 }, onFinish: { _, _, _ in })
        func play(_ provider: String) {
            let song = Track(discID: "album", number: "1", title: "", artists: "", albumTitle: "", coverURL: nil,
                             remoteSource: .init(providerID: provider, itemID: "1"))
            reporting.begin(song, sourceID: nil)
            reporting.setPlaying(true)
        }
        play("first")
        reporting.unregister("first")
        play("first")
        play("second")
        #expect(first == 1 && second == 1 && history == 3)
    }
}

@MainActor struct PlaybackHistoryIsolationTests {
    @Test func legacyHistoryDecodesAndNewProvidersUseTheirOwnNamespace() throws {
        let name = "PlaybackHistoryIsolation.\(UUID())"
        let defaults = try #require(UserDefaults(suiteName: name))
        defer { defaults.removePersistentDomain(forName: name) }
        let old = PlaybackHistoryStore.Entry(kind: .neteaseAlbum, itemID: "7", title: "old", subtitle: "", playedAt: .now)
        defaults.set(try JSONEncoder().encode([old]), forKey: "playbackHistory.v1")
        let history = PlaybackHistoryStore(defaults: defaults)
        #expect(history.entries.first?.providerID == "netease")
        history.register("custom", albumID: { $0.discID })
        let song = Track(discID: "7", number: "1", title: "", artists: "", albumTitle: "new", coverURL: nil,
                         remoteSource: .init(providerID: "custom", itemID: "1"))
        history.record(song)
        #expect(history.entries.count == 2)
        #expect(history.entries.first?.providerID == "custom")
        history.unregister("custom")
        history.record(Track(discID: "8", number: "1", title: "", artists: "", albumTitle: "ignored", coverURL: nil,
                             remoteSource: .init(providerID: "custom", itemID: "2")))
        #expect(history.entries.count == 2)
        #expect(PlaybackHistoryStore(defaults: defaults).entries.first?.providerID == "custom")
    }
}
