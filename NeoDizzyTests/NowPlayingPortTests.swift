import Foundation
import Observation
import SwiftUI
import Synchronization
import UIKit
import Testing
@testable import NeoDizzy

@Suite(.serialized) @MainActor struct NowPlayingPortTests {
    @Test(arguments: [NowPlayingPage.artwork, .queue])
    func popupMotionDoesNotInvalidatePlayerContentGeometry(page: NowPlayingPage) async throws {
        let name = "PlayerGeometryTests.\(UUID())"
        let defaults = try #require(UserDefaults(suiteName: name))
        defer { defaults.removePersistentDomain(forName: name) }
        let tracks = (0..<8).map {
            Track(discID: "", number: "\($0)", title: "几何测试 \($0)", artists: "测试艺术家",
                  albumTitle: "专辑", coverURL: nil,
                  localSource: .init(albumID: "test", trackID: "\($0)"))
        }
        let persistence = PlaybackPersistence(defaults: defaults)
        persistence.save(.init(queue: tracks, currentIndex: 0, progress: 0,
                               repeatMode: .off, isShuffled: false, shuffledOrder: []))
        let player = PlayerStore(persistence: persistence)
        player.restore()
        let library = OfflineLibraryStore(defaults: defaults)
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let favorites = FavoritesStore(directory: directory)
        let modules = try ModuleRegistry([LocalLibraryModule(library: library)])
        let geometry = NowPlayingGeometry()
        let hosting = UIHostingController(rootView: NowPlayingView(initialPage: page, geometry: geometry)
            .environment(player).environment(library).environment(favorites).environment(modules))
        // Isolate presentation movement from actual safe-area/layout changes.
        hosting.safeAreaRegions = []
        let parent = UIViewController()
        let scene = try #require(UIApplication.shared.connectedScenes.first as? UIWindowScene)
        let window = UIWindow(windowScene: scene)
        window.rootViewController = parent
        window.makeKeyAndVisible()
        parent.addChild(hosting)
        hosting.view.frame = parent.view.bounds
        parent.view.addSubview(hosting.view)
        hosting.didMove(toParent: parent)
        defer {
            hosting.willMove(toParent: nil)
            hosting.view.removeFromSuperview()
            hosting.removeFromParent()
            window.isHidden = true
            window.rootViewController = nil
        }

        func waitUntil(_ condition: () -> Bool) async throws {
            let deadline = ContinuousClock.now.advanced(by: .seconds(5))
            while !condition(), ContinuousClock.now < deadline {
                try await Task.sleep(for: .milliseconds(20))
            }
            #expect(condition())
        }
        try await waitUntil { geometry.contentSize.width > 0 && geometry.backdropFrame.width > 0 }
        try await Task.sleep(for: .milliseconds(150))
        let initialContent = geometry.contentFrame
        let initialBackdrop = geometry.backdropFrame
        let initialCenter = hosting.view.center
        let initialScreenFrame = hosting.view.convert(hosting.view.bounds, to: window)
        let changes = Mutex(0)
        withObservationTracking {
            _ = geometry.contentFrame
            _ = geometry.backdropFrame
        } onChange: {
            changes.withLock { $0 += 1 }
        }

        // LN moves and gathers the UIKit content host during an interactive close.
        // Screen geometry must change without publishing that motion into SwiftUI.
        for (translation, scale): (CGFloat, CGFloat) in [(24, 1), (80, 0.97), (140, 0.92), (60, 0.98), (0, 1)] {
            hosting.view.center = CGPoint(x: initialCenter.x, y: initialCenter.y + translation)
            hosting.view.transform = CGAffineTransform(scaleX: scale, y: scale)
            window.layoutIfNeeded()
            try await Task.sleep(for: .milliseconds(60))
            let screenFrame = hosting.view.convert(hosting.view.bounds, to: window)
            #expect(abs(screenFrame.midY - initialScreenFrame.midY - translation) < 1)
            #expect(abs(screenFrame.width - initialScreenFrame.width * scale) < 1)
            if translation != 0 { #expect(screenFrame != initialScreenFrame) }
            #expect(geometry.contentFrame == initialContent)
            #expect(geometry.backdropFrame == initialBackdrop)
            #expect(changes.withLock { $0 } == 0)
        }

        // Genuine bounds changes still invalidate layout; this must not become a
        // frozen one-time measurement just to suppress dismissal updates.
        let resized = CGSize(width: hosting.view.bounds.width - 24, height: hosting.view.bounds.height - 96)
        hosting.view.frame = CGRect(origin: .zero, size: resized)
        hosting.view.setNeedsLayout()
        hosting.view.layoutIfNeeded()
        try await waitUntil {
            geometry.contentSize == resized && geometry.backdropFrame.size != initialBackdrop.size
        }
        #expect(geometry.contentFrame.origin == .zero)
        #expect(changes.withLock { $0 } > 0)
    }

    @Test func slowQueueScrollKeepsViewportAndContentStableAcrossHeaderBoundary() async throws {
        let name = "QueueScrollTests.\(UUID())"
        let defaults = try #require(UserDefaults(suiteName: name))
        defer { defaults.removePersistentDomain(forName: name) }
        let tracks = (0..<30).map {
            Track(discID: "", number: "\($0)", title: "队列歌曲 \($0)", artists: "测试艺术家", albumTitle: "专辑", coverURL: nil,
                  localSource: .init(albumID: "test", trackID: "\($0)"))
        }
        let persistence = PlaybackPersistence(defaults: defaults)
        persistence.save(.init(queue: tracks, currentIndex: 0, progress: 0, repeatMode: .off, isShuffled: false, shuffledOrder: []))
        let player = PlayerStore(persistence: persistence)
        player.restore()
        let library = OfflineLibraryStore(defaults: defaults)
        let favoritesDirectory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: favoritesDirectory) }
        let favorites = FavoritesStore(directory: favoritesDirectory)
        let modules = try ModuleRegistry([LocalLibraryModule(library: library)])
        let controller = UIHostingController(rootView: NowPlayingView(initialPage: .queue)
            .environment(player).environment(library).environment(favorites).environment(modules))
        let scene = try #require(UIApplication.shared.connectedScenes.first as? UIWindowScene)
        let window = UIWindow(windowScene: scene)
        window.rootViewController = controller
        window.makeKeyAndVisible()
        defer { window.isHidden = true; window.rootViewController = nil }
        try await Task.sleep(for: .milliseconds(500))

        func collectionViews(in view: UIView) -> [UICollectionView] {
            (view as? UICollectionView).map { [$0] } ?? view.subviews.flatMap { collectionViews(in: $0) }
        }
        let list = try #require(collectionViews(in: controller.view).max { $0.bounds.height < $1.bounds.height })
        let initialViewport = list.convert(list.bounds, to: window)
        // Inspect the visible "Continue Playing" row, not contentSize: List
        // legitimately refines estimated heights of offscreen rows on scroll.
        let headingIndex = IndexPath(item: 0, section: list.numberOfSections - 1)
        let initialHeading = try #require(list.layoutAttributesForItem(at: headingIndex)).frame
        // Cross the old 72 pt handoff in both directions, including fractional
        // offsets. Changing container/header heights here used to move the list
        // and its "Continue Playing" row during a slow drag.
        let offsets: [CGFloat] = [60, 68, 71, 71.5, 72, 72.5, 73, 80, 73, 72, 71.5, 68, 60, 0]
        for offset in offsets {
            let target = offset - list.adjustedContentInset.top
            list.setContentOffset(CGPoint(x: 0, y: target), animated: false)
            try await Task.sleep(for: .milliseconds(100))
            window.layoutIfNeeded()
            let viewport = list.convert(list.bounds, to: window)
            #expect(abs(viewport.minY - initialViewport.minY) < 1)
            #expect(abs(viewport.height - initialViewport.height) < 1)
            let heading = try #require(list.layoutAttributesForItem(at: headingIndex)).frame
            #expect(abs(heading.minY - initialHeading.minY) < 1)
            #expect(abs(list.contentOffset.y - target) < 1)
        }
        for (offset, name): (CGFloat, String) in [(36, "queue-partially-scrolled"), (110, "queue-pinned-controls")] {
            list.setContentOffset(CGPoint(x: 0, y: offset - list.adjustedContentInset.top), animated: false)
            try await Task.sleep(for: .milliseconds(150))
            let image = UIGraphicsImageRenderer(bounds: window.bounds).image { _ in
                window.drawHierarchy(in: window.bounds, afterScreenUpdates: true)
            }
            if let data = image.pngData() { Attachment.record(data, named: "\(name).png") }
        }
    }

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
        let modules = try ModuleRegistry([LocalLibraryModule(library: library)])
        let controller = UIHostingController(rootView: NowPlayingView(initialPage: page)
            .environment(player).environment(library).environment(favorites).environment(modules).frame(width: size.width, height: size.height))
        let scene = try #require(UIApplication.shared.connectedScenes.first as? UIWindowScene)
        let window = UIWindow(windowScene: scene)
        window.rootViewController = controller
        window.makeKeyAndVisible()
        defer { window.isHidden = true; window.rootViewController = nil }
        try await Task.sleep(for: .milliseconds(450))
        #expect(controller.view.window != nil)
        #expect(player.currentTrack == track && !player.isPlaying)
        if !landscape {
            let image = UIGraphicsImageRenderer(bounds: window.bounds).image { _ in
                window.drawHierarchy(in: window.bounds, afterScreenUpdates: true)
            }
            if let data = image.pngData() { Attachment.record(data, named: "player-\(page)-layout.png") }
        }
    }
}
