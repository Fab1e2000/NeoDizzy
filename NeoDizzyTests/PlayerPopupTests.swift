import LNPopupUI
import Nuke
import SwiftUI
import Testing
import UIKit
@testable import NeoDizzy

@Suite(.serialized) @MainActor struct PlayerPopupTests {
    @Test func popupPanLeavesHorizontalTitleDraggingToTrackSwipe() {
        let delegate = PlayerPopupAppearance()
        let view = UIView(frame: CGRect(x: 0, y: 0, width: 300, height: 50))
        let pan = DirectionTestPan()
        view.addGestureRecognizer(pan)
        pan.travel = CGPoint(x: 50, y: 4)
        #expect(!delegate.gestureRecognizerShouldBegin(pan))
        pan.travel = CGPoint(x: 4, y: -50)
        #expect(delegate.gestureRecognizerShouldBegin(pan))
    }

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
        let cover = UIGraphicsImageRenderer(size: CGSize(width: 16, height: 16)).image { context in
            UIColor.red.setFill()
            context.fill(CGRect(x: 0, y: 0, width: 16, height: 16))
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
        let window = UIWindow(windowScene: scene)
        window.rootViewController = controller
        window.makeKeyAndVisible()
        defer { window.isHidden = true; window.rootViewController = nil }

        try await waitUntil { popupContainer(in: controller) != nil }
        let container = try #require(popupContainer(in: controller))
        #expect(container.popupPresentationState == .barPresented)
        // Page-local artwork appearance must reach LN, then restore the window's mode on pop.
        state.pageScheme = .dark
        try await waitUntil { container.popupBar.traitCollection.userInterfaceStyle == .dark }
        try await Task.sleep(for: .milliseconds(350))
        recordAppearance(window, named: "mini-dark.png")
        state.pageScheme = .light
        try await waitUntil { container.popupBar.traitCollection.userInterfaceStyle == .light }
        try await Task.sleep(for: .milliseconds(350))
        recordAppearance(window, named: "mini-light.png")
        state.pageScheme = .dark
        try await waitUntil { container.popupBar.overrideUserInterfaceStyle == .dark }
        // The bar requests its thumbnail even before the full player has appeared.
        var imageRequest = ImageRequest(url: coverURL)
        imageRequest.thumbnail = .init(size: CGSize(width: 160, height: 160), unit: .pixels,
                                       contentMode: .aspectFill)
        try await waitUntil { ImagePipeline.shared.cache.cachedImage(for: imageRequest) != nil }
        // Exercise LN's public inline trait, the same signal sent by tab minimization.
        let content = try #require(container.popupContent)
        content.traitOverrides[LNPopupBar.EnvironmentTrait.self] = .inline
        try await waitUntil { titlePan(in: container.popupBar) != nil }
        let compactPan = try #require(titlePan(in: container.popupBar))
        let titleView = try #require(compactPan.view)
        let compactHeight = titleView.bounds.height
        let titleFrame = titleView.convert(titleView.bounds, to: window)
        let artworkView = container.popupBar.imageView
        let artworkFrame = artworkView.convert(artworkView.bounds, to: window)
        #expect(titleFrame.minX >= artworkFrame.maxX)
        #expect(titleFrame.width > 0)
        recordAppearance(window, named: "mini-inline.png")
        content.traitOverrides[LNPopupBar.EnvironmentTrait.self] = .regular
        try await waitUntil { (titlePan(in: container.popupBar)?.view?.bounds.height ?? 0) > compactHeight }
        recordAppearance(window, named: "mini-title-swipe-regular.png")
        state.isPresented = true
        try await waitUntil { container.popupPresentationState == .open }
        // The adapter keeps its explicitly supplied appearance while content is open.
        try await Task.sleep(for: .milliseconds(100))
        #expect(container.popupBar.overrideUserInterfaceStyle == .dark)
        #expect(container.popupContent?.view.window != nil)
        #expect(player.currentTrack?.title == track.title)

        // Native closure (also used by the drag interaction) must update SwiftUI and routing callback.
        container.closePopup(animated: false)
        try await waitUntil { !state.isPresented && state.closeCount == 1 }
        #expect(container.popupPresentationState == .barPresented)
        #expect(container.popupBar.overrideUserInterfaceStyle == .dark)

        state.isPresented = true
        try await waitUntil { container.popupPresentationState == .open }
        state.isPresented = false
        let deadline = ContinuousClock.now.advanced(by: .seconds(5))
        while container.popupPresentationState != .barPresented, ContinuousClock.now < deadline {
            #expect(container.popupBar.traitCollection.userInterfaceStyle == .dark)
            try await Task.sleep(for: .milliseconds(16))
        }
        try await waitUntil { container.popupPresentationState == .barPresented && state.closeCount == 2 }

        state.isSuppressed = true
        try await waitUntil { container.popupPresentationState == .barHidden }
        state.isSuppressed = false
        try await waitUntil { container.popupPresentationState == .barPresented }
        #expect(player.currentTrack == track && !player.isPlaying)
    }

    private func titlePan(in view: UIView) -> UIGestureRecognizer? {
        if let pan = view.gestureRecognizers?.first(where: { $0.name == "NeoDizzy.NowPlayingTrackSwipe" }) { return pan }
        return view.subviews.lazy.compactMap { titlePan(in: $0) }.first
    }

    private func popupContainer(in controller: UIViewController) -> UIViewController? {
        if controller.popupPresentationState != .barHidden { return controller }
        return controller.children.lazy.compactMap { popupContainer(in: $0) }.first
    }

    private func recordAppearance(_ window: UIWindow, named name: String) {
        let image = UIGraphicsImageRenderer(bounds: window.bounds).image { _ in
            window.drawHierarchy(in: window.bounds, afterScreenUpdates: true)
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
            // Match the app's tab container; a single-tab SwiftUI host can
            // elide the UITabBarController that LN docks to.
            Tab("搜索", systemImage: "magnifyingglass") { Color.clear }
        }
        .modifier(PlayerPopup(isPresented: $state.isPresented, isSuppressed: state.isSuppressed,
                              colorScheme: state.pageScheme ?? .light) {
            state.closeCount += 1
        })
    }
}

@MainActor private final class DirectionTestPan: UIPanGestureRecognizer {
    var travel = CGPoint.zero
    override func translation(in view: UIView?) -> CGPoint { travel }
}
