import SwiftUI
import UIKit

struct RootView: View {
    @State private var host: ModuleHost
    let modules: ModuleRegistry
    private var tabSettings: ModuleSettings { host.settings }
    @State private var settingsPresentation = AppSettingsPresentation()
    @State private var search = SearchPresentation()
    @State private var themeIcon = ThemeIconController()
    @State private var libraryBackup = LibraryBackup()
    private let appearance = AppearanceSettings.shared
    let services: AppServices
    private var player: PlayerStore { services.player }
    private var offlineLibrary: OfflineLibraryStore { services.offlineLibrary }
    @State private var nowPlaying = NowPlayingPresentation()
    @State private var pendingPlayerRoute: AppRoute?
    @Namespace private var playerTransition
    /// 沉浸模式：隐藏屏幕顶部的时间、电量等状态栏信息（设置 › 外观）。
    /// 与 MeloX 相同：页面可以临时收起迷你播放器（多选时给底部操作栏让位）。
    @State private var isMiniPlayerSuppressed = false
    @AppStorage(ImmersiveMode.storageKey) private var isImmersive = false
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
            .environment(services.favorites)
            .environment(services.accountLibrary)
            .environment(services.playbackHistory)
            .environment(themeIcon)
            .environment(libraryBackup)
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
            // 一次搜索所有来源，取代各页面自己的搜索框。
            Tab(value: ModuleID.search, role: .search) {
                MainNavigationStack(path: path(for: .search)) { UnifiedSearchView() }
            }
        }
        .onChange(of: host.selection) { _, selection in
            if selection == .search { search.isActive = true }
        }
        .environment(search)
        .environment(\.setMiniPlayerSuppressed, SetMiniPlayerSuppressedAction { isMiniPlayerSuppressed = $0 })
        .onChange(of: tabSettings.visibleModules, initial: true) { _, _ in
            host.reconcileSelection()
        }
        // 与 MeloX 相同：向下滚动时标签栏收起，迷你播放器缩成一行（inline）跟在旁边；往回滚恢复。
        .tabBarMinimizeBehavior(.onScrollDown)
        // 有曲目时在标签栏上方显示迷你播放器，点击打开播放页。
        // 与 MeloX 相同：没有歌曲时不显示迷你播放器；页面要求时临时收起。
        .tabViewBottomAccessory(isEnabled: player.currentTrack != nil && !isMiniPlayerSuppressed) {
            MiniPlayerView(transitionNamespace: playerTransition) { nowPlaying.isPresented = true }
        }
        // 齿轮始终打开同一个全局设置页；账号由模块呈现。
        .environment(settingsPresentation)
        .sheet(isPresented: $settingsPresentation.isPresented, onDismiss: {
            // 设置里点了平台账号：等设置收起后再弹出该平台的登录或账号页。
            guard let id = settingsPresentation.pendingAccount else { return }
            settingsPresentation.pendingAccount = nil
            modules.openAccount(for: id)
        }) {
            // 弹层不在上面 .environment 的作用范围内，要单独传入。
            AppSettingsView().environment(settingsPresentation)
                .statusBarHidden(isImmersive)
        }
        // 播放页全屏展开：从迷你播放器的封面放大出来，下拉收起。
        .fullScreenCover(isPresented: $nowPlaying.isPresented, onDismiss: finishPlayerNavigation) {
            NowPlayingView()
                .presentationBackground(.clear)
                .presentationContentInteraction(.resizes)
                .navigationTransition(.zoom(sourceID: NowPlayingView.transitionID, in: playerTransition))
                .statusBarHidden(isImmersive)
        }
        .statusBarHidden(isImmersive)
        .onOpenURL { modules.handleURL($0, host: host) }
        // 本机喜欢、收藏后立刻更新资料库；换账号时重新同步。
        .onChange(of: services.netease.library.revision) { _, _ in services.accountLibrary.rebuildNetease(from: services.netease) }
        .onChange(of: services.netease.profile?.userId) { _, _ in services.favorites.updateAccounts(); Task { await services.syncAccountLibrary(force: true) } }
        .onChange(of: services.account.account?.userID) { _, _ in Task { await services.syncAccountLibrary(force: true) } }
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
            // 资料库只在启动和回到前台时与账号同步一次，浏览时不刷新。
            if phase == .active, oldPhase == .background || oldPhase == phase {
                Task { await services.syncAccountLibrary(force: oldPhase == .background) }
            }
            if phase == .background {
                player.saveState()
            }
            // 自动备份到期就覆盖上次导出的文件；进入后台时向系统多要一点时间写完。
            if phase != .inactive, libraryBackup.isDue {
                let task = UIApplication.shared.beginBackgroundTask(withName: "LibraryBackup")
                Task {
                    await libraryBackup.runIfDue(libraryContext)
                    if task != .invalid { UIApplication.shared.endBackgroundTask(task) }
                }
            }
        }
    }

    private var libraryContext: LibraryContext {
        LibraryContext(favorites: services.favorites, mirror: services.accountLibrary, saved: services.savedLibrary,
                       offline: offlineLibrary, netease: services.netease, modules: tabSettings, downloads: services.downloads)
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
