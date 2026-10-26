import LNPopupUI
import ObjectiveC
import SwiftUI
import Testing
import UIKit
@testable import NeoDizzy

@Suite(.serialized) @MainActor struct PlayerPopupTests {
    @Test func controlsKeepTheirSizeAcrossPlaybackAndBuffering() {
        var sizes: [CGSize] = []
        for (playing, loading) in [(false, false), (true, false), (true, true)] {
            let controller = UIHostingController(rootView: MiniPlayerControls(
                isPlaying: playing, isLoading: loading, canPlayNext: true, compact: false,
                colorScheme: .dark, togglePlayback: {}, next: {}))
            sizes.append(controller.sizeThatFits(in: CGSize(width: 400, height: 100)))
        }
        #expect(sizes.allSatisfy { $0 == sizes.first })
        let compact = UIHostingController(rootView: MiniPlayerControls(
            isPlaying: false, isLoading: false, canPlayNext: true, compact: true,
            colorScheme: .dark, togglePlayback: {}, next: {}))
        let compactSize = compact.sizeThatFits(in: CGSize(width: 400, height: 100))
        #expect(compactSize.width < sizes[0].width)
        #expect(compactSize.height == sizes[0].height)
    }

    @Test func popupSynchronizesNativeDismissalAndSuppression() async throws {
        let name = "PlayerPopupTests.\(UUID())"
        let defaults = try #require(UserDefaults(suiteName: name))
        defer { defaults.removePersistentDomain(forName: name) }
        let coverURL = FileManager.default.temporaryDirectory.appendingPathComponent("\(UUID()).png")
        // Match real downloaded artwork: a tiny fixture hides UIImageView's
        // intrinsic-height overflow inside the SwiftUI miniature frame.
        let cover = UIGraphicsImageRenderer(size: CGSize(width: 900, height: 900)).image { context in
            UIColor.red.setFill()
            context.fill(CGRect(x: 0, y: 0, width: 900, height: 900))
        }
        try #require(cover.pngData()).write(to: coverURL)
        defer { try? FileManager.default.removeItem(at: coverURL) }
        let track = Track(discID: "", number: "1", title: "转场测试", artists: "艺术家",
                          albumTitle: "专辑", coverURL: coverURL,
                          localSource: .init(albumID: "test", trackID: UUID().uuidString))
        let persistence = PlaybackPersistence(defaults: defaults)
        persistence.save(.init(queue: [track], currentIndex: 0, progress: 0,
                               repeatMode: .off, isShuffled: false, shuffledOrder: []))
        let player = PlayerStore(persistence: persistence)
        player.restore()
        let library = OfflineLibraryStore(defaults: defaults)
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let favorites = FavoritesStore(directory: directory)
        let modules = try ModuleRegistry([LocalLibraryModule(library: library)])
        let state = PopupTestState()
        let controller = UIHostingController(rootView: PopupTestHost(state: state)
            .environment(player).environment(library).environment(favorites).environment(modules))
        let scene = try #require(UIApplication.shared.connectedScenes.first as? UIWindowScene)
        let previousKeyWindow = scene.windows.first(where: \.isKeyWindow)
        let window = UIWindow(windowScene: scene)
        window.rootViewController = controller
        window.makeKeyAndVisible()
        defer {
            window.isHidden = true
            window.rootViewController = nil
            previousKeyWindow?.makeKey()
        }

        try await waitUntil {
            guard let tab = tabController(in: controller) else { return false }
            return hasVisibleAccessory(tab)
        }
        let tab = try #require(tabController(in: controller))
        let accessory = try #require(tab.bottomAccessory)
        let tabInsets = tab.view.safeAreaInsets
        let additionalInsets = tab.additionalSafeAreaInsets
        let accessoryFrame = accessory.contentView.convert(accessory.contentView.bounds, to: window)
        #expect(accessory.contentView.window === window)
        #expect(presentedPlayer(in: controller) == nil)
        recordAppearance(window, named: "native-mini.png")

        state.isPresented = true
        try await waitUntil { presentedPlayer(in: controller)?.popupPresentationState == .open }
        let presented = try #require(presentedPlayer(in: controller))
        #expect(presented.view.window === window)
        #expect(presented.view.traitCollection.userInterfaceStyle == .dark)
        // LN owns a separate ordinary host. The real tab controller only owns the system accessory.
        #expect(presented.tabBarController == nil)
        #expect(tab.popupPresentationState == .barHidden)
        #expect(presented.additionalSafeAreaInsets == .zero)
        let source = try #require(presented.popupBar.externalTransitionSource)
        #expect(source.interactionShouldBegin != nil)
        #expect(source.containerView === accessory.contentView)
        let sourceContent = try #require(source.contentView)
        let sourceArtwork = try #require(source.artworkView as? UIImageView)
        #expect(sourceContent.window === window)
        #expect(sourceArtwork.window === window)
        #expect(sourceArtwork.isDescendant(of: sourceContent))
        #expect(sourceArtwork.image != nil)
        #expect(sourceContent.bounds.width > 0 && sourceContent.bounds.height > 0)
        #expect(sourceArtwork.bounds.width > 0 && sourceArtwork.bounds.height > 0)
        #expect(abs(sourceArtwork.bounds.width - sourceArtwork.bounds.height) < 0.5,
                "LN must receive the actual square miniature bounds, not a clipped full-size image")
        #expect(sourceArtwork.bounds.height <= sourceContent.bounds.height)
        #expect(tab.additionalSafeAreaInsets == additionalInsets)
        #expect(accessory.contentView.convert(accessory.contentView.bounds, to: window) == accessoryFrame)
        // Presenting the full player must not remove the system accessory or its layout space.
        #expect(tab.bottomAccessory != nil)
        #expect(tab.view.safeAreaInsets == tabInsets)
        #expect(state.closeCount == 0)
        recordAppearance(window, named: "ln-external-open.png")

        // Native dismissal, including the completed drag route, synchronizes SwiftUI exactly once.
        presented.dismiss(animated: false)
        try await waitUntil { !state.isPresented && state.closeCount == 1 && presentedPlayer(in: controller) == nil }
        #expect(tab.bottomAccessory != nil)
        #expect(tab.view.safeAreaInsets == tabInsets)

        state.isPresented = true
        try await waitUntil { presentedPlayer(in: controller)?.popupPresentationState == .open }
        let measuredClose = try #require(presentedPlayer(in: controller))
        let closeContainer = try #require(measuredClose.popupBar.externalTransitionSource?.containerView)
        #expect(closeContainer === tab.bottomAccessory?.contentView)
        state.isPresented = false
        let closeStarted = ContinuousClock.now
        let closeDeadline = closeStarted.advanced(by: .seconds(5))
        var recordedClosingFrame = false
        var checkedCloseTarget = false
        while presentedPlayer(in: controller) != nil, ContinuousClock.now < closeDeadline {
            if let wrapper = measuredClose.popupContentView.value(forKey: "transitionView") as? UIView,
               let parent = wrapper.superview, !checkedCloseTarget {
                let target = closeContainer.convert(closeContainer.bounds, to: parent)
                #expect(abs(wrapper.frame.minX - target.minX) < 0.5)
                #expect(abs(wrapper.frame.minY - target.minY) < 0.5)
                #expect(abs(wrapper.frame.width - target.width) < 0.5)
                #expect(abs(wrapper.frame.height - target.height) < 0.5)
                try checkTransitionSurfaces(wrapper, host: measuredClose,
                                            accessory: closeContainer)
                checkedCloseTarget = true
            }
            // The external-source path must leave the browser's geometry alone throughout close.
            #expect(tab.popupPresentationState == .barHidden)
            #expect(tab.view.safeAreaInsets == tabInsets)
            #expect(tab.additionalSafeAreaInsets == additionalInsets)
            #expect(accessory.contentView.convert(accessory.contentView.bounds, to: window) == accessoryFrame)
            if !recordedClosingFrame, ContinuousClock.now - closeStarted >= .milliseconds(120) {
                recordAppearance(window, named: "ln-external-closing-120ms.png", afterScreenUpdates: false)
                recordedClosingFrame = true
            }
            try await Task.sleep(for: .milliseconds(16))
        }
        #expect(checkedCloseTarget, "The close portal must land in the public accessory container")
        #expect(recordedClosingFrame)
        try await waitUntil { presentedPlayer(in: controller) == nil && state.closeCount == 2 }
        #expect(tab.bottomAccessory != nil)
        #expect(tab.view.safeAreaInsets == tabInsets)

        // A new open request during the real LN close must survive the old host's completion.
        state.isPresented = true
        try await waitUntil { presentedPlayer(in: controller)?.popupPresentationState == .open }
        let closingPlayer = try #require(presentedPlayer(in: controller))
        let openContentFrame = closingPlayer.popupContentView.frame
        state.isPresented = false
        try await waitUntil { closingPlayer.popupContentView.frame != openContentFrame }
        #expect(presentedPlayer(in: controller) === closingPlayer)
        #expect(state.closeCount == 2)
        state.isPresented = true
        let reopenDeadline = ContinuousClock.now.advanced(by: .seconds(5))
        while ContinuousClock.now < reopenDeadline {
            #expect(state.isPresented)
            #expect(state.closeCount == 2)
            if let active = presentedPlayer(in: controller),
               active !== closingPlayer, active.popupPresentationState == .open { break }
            try await Task.sleep(for: .milliseconds(16))
        }
        let reopenedPlayer = try #require(presentedPlayer(in: controller))
        #expect(reopenedPlayer !== closingPlayer)
        #expect(reopenedPlayer.popupPresentationState == .open)
        #expect(state.isPresented && state.closeCount == 2)
        #expect(tab.view.safeAreaInsets == tabInsets)
        #expect(tab.additionalSafeAreaInsets == additionalInsets)
        state.isPresented = false
        try await waitUntil { presentedPlayer(in: controller) == nil && state.closeCount == 3 }

        // Suppressing the miniature while open also completes dismissal before routing is notified.
        state.isPresented = true
        try await waitUntil { presentedPlayer(in: controller)?.popupPresentationState == .open }
        state.isSuppressed = true
        try await waitUntil {
            !state.isPresented && presentedPlayer(in: controller) == nil
                && !hasVisibleAccessory(tab) && state.closeCount == 4
        }
        state.isSuppressed = false
        try await waitUntil { hasVisibleAccessory(tab) }
        try await Task.sleep(for: .milliseconds(150))
        #expect(state.closeCount == 4)
        #expect(player.currentTrack == track && !player.isPlaying)
    }

    /// Simulated recognizer inputs drive LN's production state machine; this is
    /// not a claim of physical-touch or device-feel acceptance.
    @Test func externalPanUsesDistanceOrDeliberateFlickAndPreservesCancelledLayout() async throws {
        try #require(!UIAccessibility.isReduceMotionEnabled, "This regression observes animated settling frames")
        let fixture = PopupGestureFixture()
        let transitionState = PlayerTransitionState()
        let controller = UIHostingController(rootView: PopupGestureHost(fixture: fixture, transitionState: transitionState))
        let scene = try #require(UIApplication.shared.connectedScenes.first as? UIWindowScene)
        let previousKeyWindow = scene.windows.first(where: \.isKeyWindow)
        let window = UIWindow(windowScene: scene)
        window.rootViewController = controller
        window.makeKeyAndVisible()
        defer {
            window.isHidden = true
            window.rootViewController = nil
            previousKeyWindow?.makeKey()
        }
        try await waitUntil { transitionState.externalSource.contentView?.window != nil }
        fixture.isPresented = true
        try await waitUntil {
            guard let host = presentedPlayer(in: controller) else { return false }
            return host.popupPresentationState == .open && !host.popupTransitionInProgress
        }
        let host = try #require(presentedPlayer(in: controller))
        let surface = try #require(fixture.surface)
        let tab = try #require(tabController(in: controller))
        let sourceContainer = try #require(transitionState.externalSource.containerView)
        #expect(sourceContainer === tab.bottomAccessory?.contentView)
        let openTop = host.popupContentView.frame.minY
        let travel = sourceContainer.convert(sourceContainer.bounds, to: host.view).minY - openTop
        #expect(travel > 0)
        let driver = try PopupRealPanDriver(host: host)
        defer { driver.restore() }
        let gate = try #require(transitionState.externalSource.interactionShouldBegin)

        // The real host's gate accepts ordinary content outside the old marker
        // regions and buttons. A scroll view yields only at its upper edge;
        // sliders keep ownership of their continuous value-adjustment gestures.
        driver.pointInHost = surface.convert(CGPoint(x: 30, y: 35), to: host.view)
        driver.velocity = CGPoint(x: 0, y: 500)
        #expect(gate(driver.recognizer))
        // Direction arbitration belongs to the real recognizer. This driver
        // supplies already-confirmed vertical input rather than synthetic touches.
        surface.scroll.setContentOffset(CGPoint(x: 0, y: -surface.scroll.adjustedContentInset.top), animated: false)
        driver.pointInHost = surface.scroll.convert(CGPoint(x: 20, y: 20), to: host.view)
        #expect(gate(driver.recognizer))
        surface.scroll.setContentOffset(CGPoint(x: 0, y: 80), animated: false)
        driver.pointInHost = surface.scroll.convert(CGPoint(x: 20, y: 100), to: host.view)
        #expect(!gate(driver.recognizer))
        surface.scroll.setContentOffset(CGPoint(x: 0, y: -surface.scroll.adjustedContentInset.top), animated: false)
        driver.pointInHost = surface.button.convert(CGPoint(x: 40, y: 20), to: host.view)
        #expect(gate(driver.recognizer))
        driver.pointInHost = surface.slider.convert(CGPoint(x: 40, y: 20), to: host.view)
        #expect(!gate(driver.recognizer))
        driver.pointInHost = surface.convert(CGPoint(x: 30, y: 35), to: host.view)

        // Slow short pulls, accidental tiny flicks, exactly half travel, and
        // cancellation all return. Real velocity is supplied to the original LN handler.
        let screenHeight = host.view.bounds.height
        let returningInputs: [(distance: CGFloat, speed: CGFloat, cancelled: Bool)] = [
            (travel * 0.1, screenHeight * 0.3, false),
            (12, screenHeight * 2, false),
            (travel * 0.5, 0, false),
            (travel * 0.7, screenHeight * 2, true)
        ]
        for input in returningInputs {
            driver.emit(.began, translation: .zero, velocity: CGPoint(x: 0, y: 800))
            driver.emit(.changed, translation: CGPoint(x: 0, y: input.distance), velocity: CGPoint(x: 0, y: 800))
            #expect(host.popupTransitionInProgress)
            #expect(!host.popupInteractionCanBegin)
            #expect(!host.isClosingPopup)
            let draggedFrame = host.popupContentView.frame
            #expect(draggedFrame.minY > 0)
            host.view.setNeedsLayout()
            host.view.layoutIfNeeded()
            #expect(abs(host.popupContentView.frame.minY - draggedFrame.minY) < 0.5,
                    "A normal layout pass must not reset an active pull to full screen")
            // Let the dragged position reach a rendered frame before releasing.
            try await Task.sleep(for: .milliseconds(20))
            driver.emit(input.cancelled ? .cancelled : .ended,
                        translation: CGPoint(x: 0, y: input.distance), velocity: CGPoint(x: 0, y: input.speed))
            #expect(!host.isClosingPopup)
            #expect(fixture.isPresented && fixture.closeCount == 0)
            // Force a real layout during the settling animation. Compare the
            // presentation layer so a model-layer endpoint cannot hide a snap.
            try await Task.sleep(for: .milliseconds(35))
            let beforeLayout = try #require(host.popupContentView.layer.presentation()?.frame.minY)
            #expect(beforeLayout > 0, "The returning player must still be between dragged and open positions")
            host.view.setNeedsLayout()
            host.view.layoutIfNeeded()
            let afterLayout = try #require(host.popupContentView.layer.presentation()?.frame.minY)
            #expect(afterLayout > 0)
            #expect(abs(afterLayout - beforeLayout) < 1)
            try await waitUntil { host.popupPresentationState == .open && !host.popupTransitionInProgress }
            #expect(fixture.isPresented && fixture.closeCount == 0)
            #expect(abs(host.popupContentView.frame.minY) < 0.5)
        }

        // Grab the production return animator before it finishes. The next
        // gesture must adopt its currently rendered position, not the open endpoint.
        driver.emit(.began, translation: .zero, velocity: CGPoint(x: 0, y: 400))
        driver.emit(.changed, translation: CGPoint(x: 0, y: travel * 0.4), velocity: CGPoint(x: 0, y: 400))
        try await Task.sleep(for: .milliseconds(20))
        driver.emit(.cancelled, translation: CGPoint(x: 0, y: travel * 0.4), velocity: .zero)
        try await Task.sleep(for: .milliseconds(35))
        #expect(host.popupTransitionInProgress && host.popupInteractionCanBegin)
        let returningFrame = try #require(host.popupContentView.layer.presentation()?.frame)
        #expect(returningFrame.minY > 0)
        let returningContentSize = host.hosting.view.bounds.size
        driver.pointInHost = CGPoint(x: host.view.bounds.midX, y: host.view.bounds.height - 100)
        #expect(gate(driver.recognizer))
        driver.emit(.began, translation: .zero, velocity: CGPoint(x: 0, y: 400))
        #expect(abs(host.popupContentView.frame.minY - returningFrame.minY) < 1)
        driver.emit(.changed, translation: CGPoint(x: 0, y: 24), velocity: CGPoint(x: 0, y: 400))
        #expect(abs(host.popupContentView.frame.minY - returningFrame.minY - 24) < 1)
        host.view.setNeedsLayout()
        host.view.layoutIfNeeded()
        #expect(host.hosting.view.bounds.size == returningContentSize)
        #expect(fixture.closeCount == 0)
        driver.emit(.cancelled, translation: CGPoint(x: 0, y: 24), velocity: .zero)
        try await waitUntil { host.popupPresentationState == .open && !host.popupTransitionInProgress }
        #expect(fixture.isPresented && fixture.closeCount == 0)

        // An intentional downward flick closes before halfway once there is
        // meaningful travel; release commits the close before its callback fires.
        driver.emit(.began, translation: .zero, velocity: CGPoint(x: 0, y: 300))
        driver.emit(.changed, translation: CGPoint(x: 0, y: travel * 0.1), velocity: CGPoint(x: 0, y: 300))
        #expect(!host.isClosingPopup)
        driver.emit(.ended, translation: CGPoint(x: 0, y: travel * 0.1), velocity: CGPoint(x: 0, y: screenHeight * 1.2))
        try await waitUntil { host.isClosingPopup }
        #expect(host.popupTransitionInProgress)
        #expect(fixture.closeCount == 0, "The close callback must wait for the transition to finish")
        try await waitUntil { !fixture.isPresented && fixture.closeCount == 1 && presentedPlayer(in: controller) == nil }
        driver.restore()

        // Opening also uses a rendered transition surface. Catch it before the
        // first open completes, then cancel back into a usable stable player.
        fixture.isPresented = true
        try await waitUntil {
            guard let active = presentedPlayer(in: controller) else { return false }
            return active.popupTransitionInProgress && active.popupInteractionCanBegin
        }
        let secondHost = try #require(presentedPlayer(in: controller))
        let secondDriver = try PopupRealPanDriver(host: secondHost)
        defer { secondDriver.restore() }
        try await Task.sleep(for: .milliseconds(35))
        let openingSurface = (secondHost.popupContentView.value(forKey: "transitionView") as? UIView)
            ?? secondHost.popupContentView
        let openingFrame = try #require(openingSurface.layer.presentation()?.frame)
        #expect(openingFrame.minY > 0)
        let openingContentSize = secondHost.hosting.view.bounds.size
        try checkTransitionSurfaces(openingSurface, host: secondHost,
                                    accessory: try #require(transitionState.externalSource.containerView))
        secondDriver.emit(.began, translation: .zero, velocity: CGPoint(x: 0, y: 400))
        #expect(abs(secondHost.popupContentView.frame.minY - openingFrame.minY) < 1)
        #expect(abs(secondHost.hosting.view.convert(secondHost.hosting.view.bounds, to: secondHost.popupContentView).midX
                    - secondHost.popupContentView.bounds.midX) < 0.5,
                "Taking over a narrow opening clip must keep the full viewport centered")
        let grabbedCornerRadii = try #require(secondHost.popupContentView.layer.value(forKey: "cornerRadii") as? NSValue)
        secondDriver.emit(.changed, translation: CGPoint(x: 0, y: 18), velocity: CGPoint(x: 0, y: 400))
        #expect(abs(secondHost.popupContentView.frame.minY - openingFrame.minY - 18) < 1)
        let draggedCornerRadii = try #require(secondHost.popupContentView.layer.value(forKey: "cornerRadii") as? NSValue)
        secondHost.view.setNeedsLayout()
        secondHost.view.layoutIfNeeded()
        #expect(secondHost.hosting.view.bounds.size == openingContentSize)
        let laidOutCornerRadii = try #require(secondHost.popupContentView.layer.value(forKey: "cornerRadii") as? NSValue)
        for (stage, value) in [("takeover", grabbedCornerRadii), ("drag", draggedCornerRadii), ("layout", laidOutCornerRadii)] {
            // LNPopupViewCorners stores leftBottom, rightBottom, rightTop,
            // leftTop in that order. Inspect the clipping layer, not a flag.
            var corners = Array(repeating: CGSize.zero, count: 4)
            corners.withUnsafeMutableBufferPointer { buffer in
                value.getValue(buffer.baseAddress!, size: MemoryLayout<CGSize>.stride * buffer.count)
            }
            #expect(corners[3].width > 0 && corners[3].height > 0,
                    "Opening \(stage) must keep the upper-left corner rounded")
            #expect(corners[2].width > 0 && corners[2].height > 0,
                    "Opening \(stage) must keep the upper-right corner rounded")
        }
        secondDriver.emit(.cancelled, translation: CGPoint(x: 0, y: 18), velocity: .zero)
        try await waitUntil { secondHost.popupPresentationState == .open && !secondHost.popupTransitionInProgress }
        #expect(fixture.isPresented && fixture.closeCount == 1)

        // A long pull stops at the accessory's top even when the finger passes
        // its bottom. Releasing must continue from that position, not rise back.
        let secondContainer = try #require(transitionState.externalSource.containerView)
        #expect(secondContainer === tab.bottomAccessory?.contentView)
        let landingFrame = secondContainer.convert(secondContainer.bounds, to: secondHost.view)
        let longPull = landingFrame.maxY - secondHost.popupContentView.frame.minY + 80
        secondDriver.emit(.began, translation: .zero, velocity: CGPoint(x: 0, y: 300))
        secondDriver.emit(.changed, translation: CGPoint(x: 0, y: longPull), velocity: CGPoint(x: 0, y: 300))
        let draggedTop = secondHost.popupContentView.frame.minY
        #expect(abs(draggedTop - landingFrame.minY) < 0.5)
        #expect(!secondHost.isClosingPopup)
        #expect(fixture.closeCount == 1)
        try await Task.sleep(for: .milliseconds(20))
        secondDriver.emit(.ended, translation: CGPoint(x: 0, y: longPull), velocity: .zero)
        let landingDeadline = ContinuousClock.now.advanced(by: .seconds(5))
        var observedLanding = false
        var previousTop = draggedTop
        while presentedPlayer(in: controller) != nil, ContinuousClock.now < landingDeadline {
            if let wrapper = secondHost.popupContentView.value(forKey: "transitionView") as? UIView,
               let presentation = wrapper.layer.presentation(), let parent = wrapper.superview {
                let visibleFrame = parent.convert(presentation.frame, to: secondHost.view)
                if !observedLanding {
                    #expect(abs(visibleFrame.minY - draggedTop) < 1,
                            "The first rendered close frame must continue from the released player")
                }
                #expect(visibleFrame.minY >= previousTop - 0.5,
                        "The released player must not move upward to find its accessory")
                #expect(abs(visibleFrame.minY - landingFrame.minY) < 1)
                #expect(secondHost.isClosingPopup && fixture.closeCount == 1)
                previousTop = visibleFrame.minY
                observedLanding = true
            }
            try await Task.sleep(for: .milliseconds(16))
        }
        #expect(observedLanding)
        try await waitUntil { !fixture.isPresented && fixture.closeCount == 2 && presentedPlayer(in: controller) == nil }
    }

    private func checkTransitionSurfaces(_ wrapper: UIView, host: NativePlayerContentController,
                                         accessory: UIView) throws {
        let full = try #require(wrapper.subviews.first {
            $0.accessibilityIdentifier == "player.transition.fullscreen"
        } as? UIVisualEffectView)
        let miniature = try #require(wrapper.subviews.first {
            $0.accessibilityIdentifier == "player.transition.accessory"
        } as? UIVisualEffectView)
        let content = try #require(full.contentView.subviews.first {
            $0.accessibilityIdentifier == "player.transition.content"
        })
        // A narrow landing clip must not squeeze the full player's layout or
        // replace its dark material with the underlying page's light material.
        #expect(content.bounds.size == host.hosting.view.bounds.size)
        #expect(abs(content.frame.midX - wrapper.bounds.midX) < 0.5)
        #expect(full.traitCollection.userInterfaceStyle == .dark)
        #expect(miniature.traitCollection.userInterfaceStyle == accessory.traitCollection.userInterfaceStyle)
        #expect(full.alpha == 1 && miniature.alpha == 1,
                "Material transitions animate effects, not effect-view opacity")
    }

    private func hasVisibleAccessory(_ tab: UITabBarController) -> Bool {
        guard let content = tab.bottomAccessory?.contentView else { return false }
        return content.window != nil && !content.isHidden && content.alpha > 0
            && content.traitCollection.tabAccessoryEnvironment != .none
    }

    private func tabController(in controller: UIViewController) -> UITabBarController? {
        if let tab = controller as? UITabBarController { return tab }
        return controller.children.lazy.compactMap { tabController(in: $0) }.first
    }

    private func presentedPlayer(in controller: UIViewController) -> NativePlayerContentController? {
        if let presented = controller.presentedViewController as? NativePlayerContentController { return presented }
        return controller.children.lazy.compactMap { presentedPlayer(in: $0) }.first
    }

    private func recordAppearance(_ window: UIWindow, named name: String, afterScreenUpdates: Bool = true) {
        let image = UIGraphicsImageRenderer(bounds: window.bounds).image { _ in
            window.drawHierarchy(in: window.bounds, afterScreenUpdates: afterScreenUpdates)
        }
        if let data = image.pngData() { Attachment.record(data, named: name) }
    }

    private func waitUntil(_ condition: () -> Bool) async throws {
        let deadline = ContinuousClock.now.advanced(by: .seconds(5))
        while !condition(), ContinuousClock.now < deadline {
            try await Task.sleep(for: .milliseconds(50))
        }
        #expect(condition())
    }
}

@MainActor @Observable private final class PopupTestState {
    var isPresented = false
    var isSuppressed = false
    var closeCount = 0
    var pageScheme: ColorScheme?
}

private struct PopupTestHost: View {
    @Bindable var state: PopupTestState
    var body: some View {
        TabView {
            Tab("资料库", systemImage: "music.note") {
                (state.pageScheme == .dark ? Color.black : Color.white)
                    .ignoresSafeArea()
                    .toolbarColorScheme(state.pageScheme ?? .light, for: .tabBar)

            }
        }
        .modifier(PlayerPopup(isPresented: $state.isPresented, isSuppressed: state.isSuppressed,
                              colorScheme: state.pageScheme ?? .light) {
            state.closeCount += 1
        })
    }
}


@MainActor @Observable private final class PopupGestureFixture {
    var isPresented = false
    var closeCount = 0
    @ObservationIgnored weak var surface: PopupGestureSurfaceView?
}

private struct PopupGestureHost: View {
    @Bindable var fixture: PopupGestureFixture
    let transitionState: PlayerTransitionState

    var body: some View {
        TabView { Tab("测试", systemImage: "music.note") { Color.white } }
            .tabViewBottomAccessory {
                PopupGestureSource(state: transitionState).frame(height: 52)
            }
            .background {
                NativePlayerPresentation(isPresented: $fixture.isPresented, state: transitionState,
                                         onClose: { fixture.closeCount += 1 }) {
                    PopupGestureSurface(fixture: fixture)
                        .background(Color.green)
                }
            }
    }
}

private struct PopupGestureSurface: UIViewRepresentable {
    let fixture: PopupGestureFixture
    func makeUIView(context: Context) -> PopupGestureSurfaceView {
        let view = PopupGestureSurfaceView()
        fixture.surface = view
        return view
    }
    func updateUIView(_ uiView: PopupGestureSurfaceView, context: Context) {}
}

private final class PopupGestureSurfaceView: UIView {
    let scroll = UIScrollView()
    let slider = UISlider()
    let button = UIButton(type: .system)

    override init(frame: CGRect) {
        super.init(frame: frame)
        backgroundColor = .clear
        scroll.contentSize = CGSize(width: 100, height: 600)
        scroll.backgroundColor = .darkGray
        button.setTitle("测试操作", for: .normal)
        addSubview(scroll)
        addSubview(slider)
        addSubview(button)
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
    override func layoutSubviews() {
        super.layoutSubviews()
        scroll.frame = CGRect(x: 20, y: 120, width: max(bounds.width - 40, 80), height: 120)
        slider.frame = CGRect(x: 20, y: 300, width: max(bounds.width - 40, 80), height: 44)
        button.frame = CGRect(x: 20, y: 380, width: max(bounds.width - 40, 80), height: 44)
    }
}

private struct PopupGestureSource: UIViewRepresentable {
    let state: PlayerTransitionState
    func makeUIView(context: Context) -> UIView {
        let content = UIView()
        content.backgroundColor = .systemGray6
        let image = UIGraphicsImageRenderer(size: CGSize(width: 100, height: 100)).image { context in
            UIColor.red.setFill()
            context.fill(CGRect(x: 0, y: 0, width: 100, height: 100))
        }
        let artwork = UIImageView(image: image)
        artwork.frame = CGRect(x: 8, y: 6, width: 40, height: 40)
        artwork.contentMode = .scaleAspectFill
        artwork.clipsToBounds = true
        content.addSubview(artwork)
        state.artwork = image
        state.externalSource.contentView = content
        state.externalSource.artworkView = artwork
        return content
    }
    func updateUIView(_ uiView: UIView, context: Context) {}
}

/// Keeps the actual installed LN recognizer and its delegate/targets. A temporary
/// Objective-C subclass supplies deterministic input values only; the original
/// LN handler, geometry, animation and delegate callbacks all execute unchanged.
@MainActor private final class PopupRealPanDriver {
    let recognizer: UIPanGestureRecognizer
    private let engine: NSObject
    private unowned let host: UIViewController
    private let originalClass: AnyClass
    private var driverClass: AnyClass?
    private var implementations: [IMP] = []
    private var phase = UIGestureRecognizer.State.possible
    private var translation = CGPoint.zero
    var velocity = CGPoint.zero
    var pointInHost = CGPoint.zero

    init(host: NativePlayerContentController) throws {
        self.host = host
        recognizer = host.popupContentView.popupInteractionGestureRecognizer
        engine = try #require(host.perform(NSSelectorFromString("_ln_popupController_nocreate"))?.takeUnretainedValue() as? NSObject)
        originalClass = try #require(object_getClass(recognizer))
        let name = "NeoDizzyPanInput_" + UUID().uuidString.replacingOccurrences(of: "-", with: "")
        let subclass = try #require(objc_allocateClassPair(originalClass, name, 0))
        driverClass = subclass
        let stateBlock: @convention(block) (AnyObject) -> Int = { [weak self] _ in self?.phase.rawValue ?? 0 }
        let translationBlock: @convention(block) (AnyObject, UIView?) -> CGPoint = { [weak self] _, _ in self?.translation ?? .zero }
        let setTranslationBlock: @convention(block) (AnyObject, CGPoint, UIView?) -> Void = { [weak self] _, point, _ in
            self?.translation = point
        }
        let confirmedVerticalBlock: @convention(block) (AnyObject) -> Bool = { _ in true }
        let velocityBlock: @convention(block) (AnyObject, UIView?) -> CGPoint = { [weak self] _, _ in self?.velocity ?? .zero }
        let locationBlock: @convention(block) (AnyObject, UIView?) -> CGPoint = { [weak self] _, view in
            guard let self else { return .zero }
            return self.host.view.convert(self.pointInHost, to: view)
        }
        try install("state", block: stateBlock, on: subclass)
        try install("translationInView:", block: translationBlock, on: subclass)
        try install("setTranslation:inView:", block: setTranslationBlock, on: subclass)
        try install("externalVerticalIntentConfirmed", block: confirmedVerticalBlock, on: subclass)
        try install("velocityInView:", block: velocityBlock, on: subclass)
        try install("locationInView:", block: locationBlock, on: subclass)
        objc_registerClassPair(subclass)
        object_setClass(recognizer, subclass)
    }

    private func install(_ name: String, block: Any, on subclass: AnyClass) throws {
        let selector = NSSelectorFromString(name)
        let method = try #require(class_getInstanceMethod(originalClass, selector))
        let implementation = imp_implementationWithBlock(block)
        implementations.append(implementation)
        #expect(class_addMethod(subclass, selector, implementation, method_getTypeEncoding(method)))
    }

    func emit(_ phase: UIGestureRecognizer.State, translation: CGPoint, velocity: CGPoint) {
        self.phase = phase
        self.translation = translation
        self.velocity = velocity
        let selector = NSSelectorFromString("_popupBarPresentationByUserPanGestureHandler:")
        typealias Handler = @convention(c) (AnyObject, Selector, UIPanGestureRecognizer) -> Void
        let handler = unsafeBitCast(engine.method(for: selector), to: Handler.self)
        handler(engine, selector, recognizer)
    }

    func restore() {
        guard let driverClass else { return }
        object_setClass(recognizer, originalClass)
        implementations.forEach { _ = imp_removeBlock($0) }
        objc_disposeClassPair(driverClass)
        self.driverClass = nil
        implementations.removeAll()
    }
}
