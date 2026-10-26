import Foundation
import Observation
import Synchronization
import Testing
@testable import NeoDizzy

@MainActor
struct LyricsPresentationTests {
    @Test func scrollingAndUnfocusedMeasurementsDoNotPublishLayoutChanges() {
        let geometry = LyricsRowGeometry()
        geometry.record(.init(height: 50, top: 200), for: 1)
        geometry.focus(on: 1)
        let changes = Mutex(0)
        withObservationTracking {
            _ = geometry.height(for: 1)
        } onChange: {
            changes.withLock { $0 += 1 }
        }

        for top in stride(from: 200.0, through: 0.0, by: -0.5) {
            geometry.record(.init(height: 50, top: top), for: 1)
            geometry.record(.init(height: 100, top: top + 60), for: 2)
        }
        #expect(changes.withLock { $0 } == 0)
        #expect(geometry.top(for: 1) == 0)
        #expect(geometry.top(for: 2) == 60)

        // Dynamic Type or a width change can reflow the focused line.
        geometry.record(.init(height: 100, top: 0), for: 1)
        #expect(changes.withLock { $0 } == 1)
        #expect(geometry.height(for: 1) == 100)
    }

    @Test func newlyActiveLineUsesItsOwnCachedHeightBeforeSelection() {
        let geometry = LyricsRowGeometry()
        geometry.record(.init(height: 50, top: 20), for: 1)
        geometry.record(.init(height: 100, top: 80), for: 2)
        geometry.focus(on: 1)

        #expect(geometry.height(for: 2) == 100)
        #expect(geometry.height(for: 99) == nil)
        geometry.focus(on: 2)
        #expect(geometry.focusedHeight == 100)
        geometry.focus(on: 99)
        #expect(geometry.focusedHeight == nil)
        geometry.record(.init(height: 150, top: 300), for: 99)
        #expect(geometry.height(for: 99) == 150)
        geometry.focus(on: nil)
        #expect(geometry.height(for: nil) == nil)
    }

    @Test func distantSeekDoesNotUseOffscreenPositionsAndAcceptsFreshGeometry() {
        let geometry = LyricsRowGeometry()
        geometry.record(.init(height: 50, top: 200), for: 1)
        geometry.discardPosition(for: 1)
        #expect(geometry.top(for: 1) == nil)
        #expect(geometry.height(for: 1) == 50)

        geometry.focus(on: 1)
        geometry.record(.init(height: 100, top: 350), for: 1)
        #expect(geometry.top(for: 1) == 350)
        #expect(geometry.height(for: 1) == 100)
        geometry.record(.init(height: .nan, top: 0), for: 1)
        geometry.record(.init(height: 100, top: .infinity), for: 1)
        #expect(geometry.top(for: 1) == 350)
        #expect(geometry.height(for: 1) == 100)
    }

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
