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

@MainActor struct SongPlaybackHistoryTests {
    @Test func recordsSongsWithoutAlbumAndKeepsSourcesSeparate() throws {
        let name = "SongHistory.\(UUID())"
        let defaults = try #require(UserDefaults(suiteName: name))
        defer { defaults.removePersistentDomain(forName: name) }
        let store = PlaybackHistoryStore(defaults: defaults)
        store.register("first") { _ in nil }
        store.register("second") { _ in nil }
        func song(_ provider: String, _ id: String) -> Track {
            Track(discID: "", number: "1", title: id, artists: "Artist", albumTitle: "", coverURL: nil,
                  remoteSource: .init(providerID: provider, itemID: id))
        }
        let first = song("first", "1"), second = song("second", "1")
        store.record(first, at: Date(timeIntervalSince1970: 1))
        store.record(second, at: Date(timeIntervalSince1970: 2))
        store.record(first, at: Date(timeIntervalSince1970: 3))
        #expect(store.songs.map(\.track) == [first, second])
        #expect(store.songs.first?.playedAt == Date(timeIntervalSince1970: 3))
        #expect(store.entries.isEmpty)
        store.unregister("first")
        store.record(song("first", "2"))
        #expect(PlaybackHistoryStore(defaults: defaults).songs.map(\.track) == [first, second])
    }

    @Test func localSongsAreBoundedAndOldAlbumHistoryIsNotInventedAsSongs() throws {
        let name = "SongHistory.\(UUID())"
        let defaults = try #require(UserDefaults(suiteName: name))
        defer { defaults.removePersistentDomain(forName: name) }
        let old = PlaybackHistoryStore.Entry(kind: .localAlbum, itemID: "album", title: "Album", subtitle: "", playedAt: .now)
        defaults.set(try JSONEncoder().encode([old]), forKey: "playbackHistory.v1")
        defaults.set(Data("invalid".utf8), forKey: "playbackHistory.songs.v1")
        let store = PlaybackHistoryStore(defaults: defaults)
        #expect(store.songs.isEmpty)
        #expect(store.entries == [old])
        for index in 0...PlaybackHistoryStore.songLimit {
            store.record(Track(discID: "", number: "\(index)", title: "Song", artists: "", albumTitle: "Album", coverURL: nil,
                               localSource: .init(albumID: "album", trackID: "\(index)")))
        }
        let restored = PlaybackHistoryStore(defaults: defaults)
        #expect(restored.songs.count == PlaybackHistoryStore.songLimit)
        #expect(restored.songs.first?.track.localSource?.trackID == "100")
        #expect(restored.songs.last?.track.localSource?.trackID == "1")
        #expect(restored.entries.count == 1)
    }
}
