import LNPopupUI
import SwiftUI
import Testing
import UIKit
@testable import NeoDizzy

@Suite(.serialized) @MainActor struct ShellChromeIntegrationTests {
    @Test func actualRootKeepsTabTintAndPopupAppearanceTogetherAcrossTabs() async throws {
        let suite = "ShellChromeIntegration.\(UUID())"
        let defaults = try #require(UserDefaults(suiteName: suite))
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { defaults.removePersistentDomain(forName: suite); try? FileManager.default.removeItem(at: directory) }
        let state = ChromeFixtureState()
        let first = ChromeFixtureModule(name: "one", accent: .init(light: 0xAA3300, dark: 0xFF9900), scheme: .dark, state: state)
        let second = ChromeFixtureModule(name: "two", accent: .init(light: 0x008833, dark: 0x33FF88), scheme: .light, state: state)
        let registrations = [first, second].map { module in
            PlatformRegistration(descriptor: module.descriptor, canDisable: false) { _ in PlatformRuntime(module: module) }
        }
        let library = OfflineLibraryStore(defaults: defaults)
        let track = Track(discID: "", number: "1", title: "很长的标题用于检查播放器文字和操作按钮的边界", artists: "艺术家",
                          albumTitle: "专辑", coverURL: nil, localSource: .init(albumID: "fixture", trackID: UUID().uuidString))
        PlaybackPersistence(defaults: defaults).save(.init(queue: [track], currentIndex: 0, progress: 0,
                                                         repeatMode: .off, isShuffled: false, shuffledOrder: []))
        let services = AppServices(registrations: registrations, defaults: defaults, library: library, storageDirectory: directory)
        services.player.restore()
        let settings = ModuleSettings(modules: services.modules.descriptors, defaults: defaults)
        let previousAccent = AppearanceSettings.shared.accent
        defer { AppearanceSettings.shared.accent = previousAccent }
        let controller = UIHostingController(rootView: RootView(services: services, modules: services.modules, settings: settings))
        let scene = try #require(UIApplication.shared.connectedScenes.first as? UIWindowScene)
        let previousKeyWindow = scene.windows.first(where: \.isKeyWindow)
        let window = UIWindow(windowScene: scene)
        window.overrideUserInterfaceStyle = .dark
        window.rootViewController = controller
        window.makeKeyAndVisible()
        defer { window.isHidden = true; window.rootViewController = nil; previousKeyWindow?.makeKey() }
        try await wait { state.host != nil && state.nowPlaying != nil && self.tabController(in: controller) != nil }
        let tab = try #require(tabController(in: controller))
        try await wait { tab.bottomAccessory != nil && tab.tabBar.traitCollection.userInterfaceStyle == .light }
        let tabInsets = tab.view.safeAreaInsets
        let additionalInsets = tab.additionalSafeAreaInsets
        expectColor(tab.tabBar.tintColor.resolvedColor(with: tab.tabBar.traitCollection), rgb: (170.0 / 255, 0.2, 0))
        try await Task.sleep(for: .milliseconds(450))
        expectColor((tab.tabBar.selectedItem?.standardAppearance ?? tab.tabBar.standardAppearance).stackedLayoutAppearance.selected.iconColor ?? .clear,
                    rgb: (170.0 / 255, 0.2, 0))
        record(window, name: "shell-fixed-light-warm.png")
        state.nowPlaying?.isPresented = true
        try await wait { self.presentedPlayer(in: controller)?.popupPresentationState == .open }
        let presented = try #require(presentedPlayer(in: controller))
        #expect(presented.view.traitCollection.userInterfaceStyle == .dark)
        #expect(presented.popupBar.externalTransitionSource != nil)
        #expect(tab.popupPresentationState == .barHidden)
        #expect(tab.additionalSafeAreaInsets == additionalInsets)
        #expect(tab.bottomAccessory != nil)
        #expect(tab.view.safeAreaInsets == tabInsets)
        state.nowPlaying?.isPresented = false
        let deadline = ContinuousClock.now.advanced(by: .seconds(5))
        while presentedPlayer(in: controller) != nil, ContinuousClock.now < deadline {
            #expect(tab.tabBar.traitCollection.userInterfaceStyle == .light)
            try await Task.sleep(for: .milliseconds(16))
        }
        try await wait { self.presentedPlayer(in: controller) == nil }
        #expect(tab.bottomAccessory != nil)
        #expect(tab.view.safeAreaInsets == tabInsets)

        state.host?.selection = second.descriptor.id
        try await wait { tab.selectedIndex == 1 && tab.tabBar.traitCollection.userInterfaceStyle == .light && tab.bottomAccessory != nil }
        try await Task.sleep(for: .milliseconds(450))
        expectColor(tab.tabBar.tintColor.resolvedColor(with: tab.tabBar.traitCollection), rgb: (0, 136.0 / 255, 0.2))
        #expect(tab.selectedIndex == 1)
        expectColor((tab.tabBar.selectedItem?.standardAppearance ?? tab.tabBar.standardAppearance).stackedLayoutAppearance.selected.iconColor ?? .clear,
                    rgb: (0, 136.0 / 255, 0.2))
        record(window, name: "shell-light-green.png")
    }

    private func tabController(in controller: UIViewController) -> UITabBarController? {
        if let tab = controller as? UITabBarController { return tab }
        return controller.children.lazy.compactMap { tabController(in: $0) }.first
    }
    private func presentedPlayer(in controller: UIViewController) -> NativePlayerContentController? {
        if let presented = controller.presentedViewController as? NativePlayerContentController { return presented }
        return controller.children.lazy.compactMap { presentedPlayer(in: $0) }.first
    }
    private func expectColor(_ color: UIColor, rgb: (CGFloat, CGFloat, CGFloat)) {
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        #expect(color.getRed(&r, green: &g, blue: &b, alpha: &a))
        #expect(abs(r - rgb.0) < 0.0001 && abs(g - rgb.1) < 0.0001 && abs(b - rgb.2) < 0.0001)
    }
    private func wait(_ condition: () -> Bool) async throws {
        let deadline = ContinuousClock.now.advanced(by: .seconds(5))
        while !condition(), ContinuousClock.now < deadline { try await Task.sleep(for: .milliseconds(50)) }
        #expect(condition())
    }
    private func record(_ window: UIWindow, name: String) {
        let image = UIGraphicsImageRenderer(bounds: window.bounds).image { _ in window.drawHierarchy(in: window.bounds, afterScreenUpdates: true) }
        if let data = image.pngData() { Attachment.record(data, named: name) }
    }
}

@MainActor private final class ChromeFixtureState {
    var host: ModuleHost?
    var nowPlaying: NowPlayingPresentation?
}

@MainActor private struct ChromeFixtureModule: AppModule {
    let descriptor: ModuleDescriptor
    let scheme: ColorScheme
    let state: ChromeFixtureState
    init(name: String, accent: AccentPalette, scheme: ColorScheme, state: ChromeFixtureState) {
        descriptor = .init(id: ModuleID(rawValue: name), title: name, systemImage: "music.note", accent: accent)
        self.scheme = scheme; self.state = state
    }
    func rootView() -> AnyView { AnyView(ChromeFixturePage(scheme: scheme, state: state)) }
    func destination(for route: AppRoute) -> AnyView? { nil }
}

private struct ChromeFixturePage: View {
    let scheme: ColorScheme
    let state: ChromeFixtureState
    @Environment(ModuleHost.self) private var host
    @Environment(NowPlayingPresentation.self) private var nowPlaying
    var body: some View {
        (scheme == .dark ? Color.black : Color.white).ignoresSafeArea()
            .onAppear { state.host = host; state.nowPlaying = nowPlaying }
    }
}
