import SwiftUI
import Testing
import UIKit
@testable import NeoDizzy

@Suite @MainActor struct MiniPlayerTitlePagerTests {
    @Test func pagingSettlesOnceAndRejectsStaleNeighbors() {
        let songs = (0..<4).map {
            Track(discID: "", number: "\($0)", title: "Song \($0)", artists: "Artist", albumTitle: "Album", coverURL: nil,
                  localSource: .init(albumID: "test", trackID: "\($0)"))
        }
        var selected: [Int] = []
        func model(_ index: Int, next: Int? = nil) -> MiniPlayerTitlePager<Text> {
            MiniPlayerTitlePager(song: songs[index], currentIndex: index,
                previous: index > 0 ? UpcomingTrack(index: index - 1, track: songs[index - 1]) : nil,
                next: next.map { UpcomingTrack(index: $0, track: songs[$0]) },
                select: { selected.append($0) }) { track, _ in Text(track.title) }
        }
        let initial = model(1, next: 2)
        let coordinator = initial.makeCoordinator()
        let view = MiniPlayerTitlePager<Text>.PagerView()
        view.frame = CGRect(x: 0, y: 0, width: 180, height: 36)
        coordinator.view = view
        view.delegate = coordinator
        var feedbackCount = 0
        coordinator.selectionFeedback = { feedbackCount += 1 }
        coordinator.update(initial)
        #expect(view.isPagingEnabled)
        #expect(view.contentOffset.x == 180)
        coordinator.scrollViewWillBeginDragging(view)
        var targetOffset = CGPoint(x: 360, y: 0)
        coordinator.scrollViewWillEndDragging(view, withVelocity: CGPoint(x: 1, y: 0), targetContentOffset: &targetOffset)
        #expect(feedbackCount == 1)
        #expect(selected.isEmpty)
        view.contentOffset.x = 360
        coordinator.scrollViewDidEndDecelerating(view)
        coordinator.scrollViewDidEndDecelerating(view)
        #expect(selected == [2])
        coordinator.update(model(2, next: 3))
        #expect(view.contentOffset.x == 180)
        coordinator.scrollViewWillBeginDragging(view)
        view.contentOffset.x = 180
        coordinator.scrollViewDidEndDragging(view, willDecelerate: false)
        #expect(selected == [2])
        // Queue changes during deceleration: never select an obsolete neighbor.
        coordinator.scrollViewWillBeginDragging(view)
        coordinator.update(model(2))
        view.contentOffset.x = 360
        coordinator.scrollViewDidEndDecelerating(view)
        #expect(selected == [2])
        #expect(view.contentOffset.x == 180)
        // External skip cancels a gesture and centers the new item.
        coordinator.scrollViewWillBeginDragging(view)
        view.contentOffset.x = 30
        coordinator.update(model(0, next: 1))
        coordinator.scrollViewDidEndDecelerating(view)
        #expect(view.contentOffset.x == 0)
        #expect(selected == [2])
        #expect(view.contentSize.width == 360)
        #expect(feedbackCount == 1)
    }
}
