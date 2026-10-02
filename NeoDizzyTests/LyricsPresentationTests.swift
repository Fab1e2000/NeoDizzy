import Foundation
import Testing
@testable import NeoDizzy

@MainActor
struct LyricsPresentationTests {
    @Test func browsingHidesControlsAndReversingRevealsThem() {
        var tracker = LyricsScrollInterfaceVisibilityTracker()
        tracker.begin(isInterfaceVisible: true)
        #expect(tracker.update(offsetDelta: 80, hideThreshold: 120) == nil)
        #expect(tracker.update(offsetDelta: 45, hideThreshold: 120) == false)
        #expect(tracker.update(offsetDelta: 10, hideThreshold: 120) == nil)
        #expect(tracker.update(offsetDelta: -1, hideThreshold: 120) == true)
    }

    @Test func separateGesturesAndDirectionChangesDoNotAccumulateDistance() {
        var tracker = LyricsScrollInterfaceVisibilityTracker()
        tracker.begin(isInterfaceVisible: true)
        #expect(tracker.update(offsetDelta: 100, hideThreshold: 120) == nil)
        tracker.end()
        tracker.begin(isInterfaceVisible: true)
        #expect(tracker.update(offsetDelta: 30, hideThreshold: 120) == nil)
        #expect(tracker.update(offsetDelta: -20, hideThreshold: 120) == nil)
        #expect(tracker.update(offsetDelta: 100, hideThreshold: 120) == nil)
        #expect(tracker.update(offsetDelta: .infinity, hideThreshold: 120) == nil)
        #expect(tracker.update(offsetDelta: 20, hideThreshold: 120) == false)
    }
}
