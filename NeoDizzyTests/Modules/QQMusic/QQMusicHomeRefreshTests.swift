import SwiftUI
import UIKit
import Testing
@testable import NeoDizzy

@MainActor @Suite(.serialized)
struct QQMusicHomeRefreshTests {
    @Test(arguments: [false, true])
    func refreshCompletionRestoresTopUnlessAlreadyScrolled(scrolledIntoContent: Bool) async throws {
        let refresh = SuspendedRefresh()
        let controller = UIHostingController(rootView: RefreshFixture(refresh: refresh))
        let scene = try #require(UIApplication.shared.connectedScenes.first as? UIWindowScene)
        let previousKeyWindow = scene.windows.first(where: \.isKeyWindow)
        let window = UIWindow(windowScene: scene)
        window.rootViewController = controller
        window.makeKeyAndVisible()
        defer {
            refresh.finish()
            window.isHidden = true
            window.rootViewController = nil
            previousKeyWindow?.makeKey()
        }

        let mounted = await eventually { refreshScrollView(in: controller.view) != nil }
        try #require(mounted, "MainTabPage must expose its native UIScrollView and UIRefreshControl")
        let scrollView = try #require(refreshScrollView(in: controller.view))
        let control = try #require(scrollView.refreshControl)
        control.beginRefreshing()
        scrollView.setContentOffset(CGPoint(x: 0, y: -scrollView.adjustedContentInset.top - 100), animated: false)
        control.sendActions(for: .valueChanged)
        let started = await eventually { refresh.started }
        try #require(started, "Native refresh-control action must invoke MainTabPage.onRefresh")
        #expect(control.isRefreshing)

        if scrolledIntoContent {
            scrollView.setContentOffset(CGPoint(x: 0, y: 320), animated: false)
        }
        // Let SwiftUI observe the actual position while the refresh is still pending.
        try await Task.sleep(for: .milliseconds(100))
        if scrolledIntoContent {
            try #require(scrollView.contentOffset.y + scrollView.adjustedContentInset.top > 200)
        } else {
            try #require(scrollView.contentOffset.y + scrollView.adjustedContentInset.top < -20)
        }

        refresh.finish()
        let finished = await eventually { refresh.completed && !control.isRefreshing }
        try #require(finished, "Completing the refresh action must stop the native refresh control")
        // UIRefreshControl removes its inset with an animation after ending refresh.
        try await Task.sleep(for: .milliseconds(350))
        let distanceFromTop = scrollView.contentOffset.y + scrollView.adjustedContentInset.top
        if scrolledIntoContent {
            #expect(distanceFromTop > 200, "Finishing refresh must not pull an already scrolled page back to the top")
        } else {
            #expect(abs(distanceFromTop) < 2, "Finishing refresh must remove the pull-down gap")
        }

        // Reproduce the reported geometry after the native spinner has disappeared.
        // This injects the residual offset; it does not claim to reproduce the OS race.
        let residualOffset = scrolledIntoContent ? 320 : -scrollView.adjustedContentInset.top - 100
        scrollView.setContentOffset(CGPoint(x: 0, y: residualOffset), animated: false)
        try await Task.sleep(for: .milliseconds(100))
        refresh.completion += 1
        try await Task.sleep(for: .milliseconds(350))
        let recoveredDistance = scrollView.contentOffset.y + scrollView.adjustedContentInset.top
        if scrolledIntoContent {
            #expect(recoveredDistance > 200, "Recovery must preserve the user's position in the content")
        } else {
            #expect(abs(recoveredDistance) < 2, "Recovery must collapse a residual pull-down offset")
        }
    }

    private func refreshScrollView(in view: UIView) -> UIScrollView? {
        if let scrollView = view as? UIScrollView, scrollView.refreshControl != nil { return scrollView }
        for child in view.subviews {
            if let found = refreshScrollView(in: child) { return found }
        }
        return nil
    }

    private func eventually(_ condition: () -> Bool) async -> Bool {
        let deadline = ContinuousClock.now.advanced(by: .seconds(2))
        while !condition(), ContinuousClock.now < deadline {
            try? await Task.sleep(for: .milliseconds(20))
        }
        return condition()
    }
}

private struct RefreshFixture: View {
    let refresh: SuspendedRefresh

    var body: some View {
        NavigationStack {
            MainTabPage(title: "刷新测试", onRefresh: { await refresh.run() }) {
                ForEach(refresh.rows, id: \.self) { index in
                    Text("内容 \(index)")
                        .frame(maxWidth: .infinity, minHeight: 64, alignment: .leading)
                }
            }
            .modifier(QQMusicHomeRefreshRecovery(completion: refresh.completion))
        }
    }
}

@MainActor @Observable
private final class SuspendedRefresh {
    private var continuation: CheckedContinuation<Void, Never>?
    private var released = false
    private(set) var started = false
    private(set) var completed = false
    var completion = 0
    private(set) var rows = Array(0..<30)

    func run() async {
        started = true
        if !released {
            await withCheckedContinuation { continuation = $0 }
        }
        // Publish replacement content before the refresh action returns, as page models do.
        rows = Array(100..<130)
        completed = true
        completion += 1
    }

    func finish() {
        released = true
        continuation?.resume()
        continuation = nil
    }
}
