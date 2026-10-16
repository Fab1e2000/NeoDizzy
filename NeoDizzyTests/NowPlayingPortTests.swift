import Foundation
import SwiftUI
import UIKit
import Testing
@testable import NeoDizzy

@Suite(.serialized) @MainActor struct NowPlayingPortTests {
    @Test func staleLyricsEntranceCannotOverrideRapidQueueSwitch() throws {
        let motion = NowPlayingPageTransition.motion
        let now = ContinuousClock.now
        var transition = NowPlayingTransitionCoordinator(initialPage: .artwork, now: now)
        transition.select(.lyrics, usesAppleMusicLyrics: true, isQueueSongHeaderHidden: false, motion: motion, now: now)
        let oldID = try #require(transition.transition?.id)
        transition.select(.queue, usesAppleMusicLyrics: true, isQueueSongHeaderHidden: false, motion: motion, now: now.advanced(by: .milliseconds(20)))
        let currentID = try #require(transition.transition?.id)
        transition.presentLyricsEntrance(requestID: oldID, motion: motion)
        transition.settleTransition(requestID: oldID)
        #expect(transition.page == .queue && transition.transition?.id == currentID)
        #expect(transition.queueOpacityTransition.targetProgress == 1)
        #expect(transition.lyricsOpacityTransition.targetProgress == 0)
        transition.settleTransition(requestID: currentID)
        #expect(transition.transition == nil)
    }

    @Test(arguments: [false, true])
    func reorderPreservesCurrentTrackAndHandlesWrappedShuffle(shuffled: Bool) {
        let tracks = (1...5).map { Track(discID: "7", number: "\($0)", title: "Song", artists: "", albumTitle: "", coverURL: nil) }
        var queue = PlaybackQueue()
        queue.restore(tracks: tracks, currentIndex: 2, isShuffled: shuffled, shuffledOrder: [0, 2, 4, 1, 3])
        let before = queue.upcomingIndices(wraps: true).map { queue.tracks[$0].id }
        queue.moveUpcomingSongs(fromOffsets: IndexSet(integer: 0), toOffset: before.count, wraps: true)
        #expect(queue.currentTrack?.id == tracks[2].id)
        #expect(queue.upcomingIndices(wraps: true).map { queue.tracks[$0].id } == Array(before.dropFirst()) + [before[0]])
        let after = queue.tracks
        queue.moveUpcomingSongs(fromOffsets: IndexSet(integer: 999), toOffset: -1, wraps: true)
        #expect(queue.tracks == after)
    }

    @Test(arguments: [NowPlayingPage.artwork, .lyrics, .queue], [false, true])
    func playerPagesMountAndDismissInPortraitAndLandscape(page: NowPlayingPage, landscape: Bool) async throws {
        let name = "NowPlayingPortTests.\(UUID())"
        let defaults = try #require(UserDefaults(suiteName: name))
        defer { defaults.removePersistentDomain(forName: name) }
        let persistence = PlaybackPersistence(defaults: defaults)
        let track = Track(discID: "", number: "1", title: "测试歌曲", artists: "测试艺术家", albumTitle: "专辑", coverURL: nil,
                          localSource: .init(albumID: "test", trackID: UUID().uuidString))
        persistence.save(.init(queue: [track, track], currentIndex: 0, progress: 0, repeatMode: .off, isShuffled: false, shuffledOrder: []))
        let player = PlayerStore(persistence: persistence)
        player.restore()
        let library = OfflineLibraryStore(defaults: defaults)
        let size = landscape ? CGSize(width: 852, height: 393) : CGSize(width: 393, height: 852)
        let favoritesDirectory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: favoritesDirectory) }
        let favorites = FavoritesStore(directory: favoritesDirectory)
        let controller = UIHostingController(rootView: NowPlayingView(initialPage: page)
            .environment(player).environment(library).environment(favorites).frame(width: size.width, height: size.height))
        let scene = try #require(UIApplication.shared.connectedScenes.first as? UIWindowScene)
        let window = UIWindow(windowScene: scene)
        window.rootViewController = controller
        window.makeKeyAndVisible()
        defer { window.isHidden = true; window.rootViewController = nil }
        try await Task.sleep(for: .milliseconds(450))
        #expect(controller.view.window != nil)
        #expect(player.currentTrack == track && !player.isPlaying)
    }
}
