import SwiftUI

struct RootView: View {
    @State private var host: ModuleHost
    let modules: ModuleRegistry
    private var tabSettings: ModuleSettings { host.settings }
    @State private var settingsPresentation = AppSettingsPresentation()
    @State private var themeIcon = ThemeIconController()
    private let appearance = AppearanceSettings.shared
    let services: AppServices
    private var player: PlayerStore { services.player }
    private var offlineLibrary: OfflineLibraryStore { services.offlineLibrary }
    @State private var nowPlaying = NowPlayingPresentation()
    @State private var pendingPlayerRoute: AppRoute?
    @Namespace private var playerTransition
    @Environment(\.scenePhase) private var scenePhase

    init(services: AppServices, modules: ModuleRegistry, settings: ModuleSettings) {
        self.services = services
        self.modules = modules
        _host = State(initialValue: ModuleHost(settings: settings))
    }

    var body: some View {
        modules.install(in: AnyView(shell))
            .tint(DizzyPalette.accent)
            .environment(modules)
            .environment(host)
            .environment(tabSettings)
            .environment(nowPlaying)
            .environment(player)
            .environment(offlineLibrary)
            .environment(services.savedLibrary)
            .environment(themeIcon)
            .environment(\.openRoute, OpenRouteAction { route in
                settingsPresentation.isPresented = false
                modules.dismissAccounts()
                if nowPlaying.isPresented {
                    pendingPlayerRoute = route
                    nowPlaying.isPresented = false
                } else {
                    host.paths[host.selection, default: []].append(route)
                }
            })
    }

    private var shell: some View {
        @Bindable var host = host
        return TabView(selection: $host.selection) {
            ForEach(tabSettings.visibleModules) { id in
                if let descriptor = modules.descriptor(for: id) {
                    Tab(descriptor.title, systemImage: descriptor.systemImage, value: id) {
                        MainNavigationStack(path: path(for: id)) { modules.rootView(for: id) }
                    }
                }
            }
        }
        .onChange(of: tabSettings.visibleModules, initial: true) { _, _ in
            host.reconcileSelection()
        }
        // 标签栏与底部播放器始终保持完整布局，不随滚动收缩。
        .tabBarMinimizeBehavior(.never)
        // 有曲目时在标签栏上方显示迷你播放器，点击打开播放页。
        .tabViewBottomAccessory(isEnabled: player.currentTrack != nil) {
            MiniPlayerView(transitionNamespace: playerTransition) { nowPlaying.isPresented = true }
        }
        // 齿轮始终打开同一个全局设置页；账号由模块呈现。
        .environment(settingsPresentation)
        .sheet(isPresented: $settingsPresentation.isPresented) {
            AppSettingsView()
        }
        // 播放页全屏展开：从迷你播放器的封面放大出来，下拉收起。
        .fullScreenCover(isPresented: $nowPlaying.isPresented, onDismiss: finishPlayerNavigation) {
            NowPlayingView()
                .presentationBackground(.clear)
                .presentationContentInteraction(.resizes)
                .navigationTransition(.zoom(sourceID: NowPlayingView.transitionID, in: playerTransition))
        }
        .onOpenURL { modules.handleURL($0, host: host) }
        .onChange(of: host.dismissPresentations) { _, shouldDismiss in
            guard shouldDismiss else { return }
            pendingPlayerRoute = nil
            modules.dismissAccounts()
            nowPlaying.isPresented = false
            settingsPresentation.isPresented = false
            host.dismissPresentations = false
        }
        // 「正在播放」小组件跟着当前歌曲换封面；换歌时取消上一次未完成的封面请求。
        .task(id: player.currentTrack?.id) { await NowPlayingWidgetBridge.update(for: player.currentTrack) }
        .onChange(of: appearance.mode, initial: true) { WindowAppearance.apply(appearance) }
        .onChange(of: appearance.themeID) { WindowAppearance.apply(appearance) }
        .task(id: "\(appearance.themeID)-\(scenePhase == .active)") {
            guard scenePhase == .active else { return }
            // 连续点选主题时只提交最后一次，系统每换一次图标都会弹提示。
            do { try await Task.sleep(for: .milliseconds(400)) } catch { return }
            await themeIcon.apply(theme: appearance.theme)
        }
        .onChange(of: scenePhase, initial: true) { oldPhase, phase in
            if phase == .active { WindowAppearance.apply(appearance) }
            // 用户可能刚在「文件」App 里往音乐文件夹放了歌。
            if oldPhase == .background, phase == .active {
                Task { await offlineLibrary.scan(refreshMetadata: false) }
            }
            if phase == .background {
                player.saveState()
            }
        }
    }

    // Finish dismissal before pushing the destination.
    private func finishPlayerNavigation() {
        guard let route = pendingPlayerRoute else { return }
        pendingPlayerRoute = nil
        host.paths[host.selection, default: []].append(route)
    }

    private func path(for tab: ModuleID) -> Binding<[AppRoute]> {
        Binding(
            get: { host.paths[tab] ?? [] },
            set: { host.paths[tab] = $0 }
        )
    }

}

/// 每个模块各自的导航栈，统一登记可推入的页面。
struct MainNavigationStack<Root: View>: View {
    @Binding var path: [AppRoute]
    @ViewBuilder var root: Root

    var body: some View {
        NavigationStack(path: $path) {
            root.navigationDestination(for: AppRoute.self) { route in
                AppRouteDestination(route: route)
            }
        }
    }
}
