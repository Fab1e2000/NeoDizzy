import SwiftUI

struct RootView: View {
    @State private var selection: MainTab = .discover
    @State private var mine = MinePresentation()
    let services: AppServices
    private var player: PlayerStore { services.player }
    private var offlineLibrary: OfflineLibraryStore { services.offlineLibrary }
    private var downloads: DownloadStore { services.downloads }
    private var account: AccountStore { services.account }
    @State private var isNowPlayingPresented = false
    /// 每个标签页的导航路径。播放页里的「前往专辑」会往当前标签页推入页面。
    @State private var paths: [MainTab: [AppRoute]] = [:]
    @Namespace private var playerTransition
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        @Bindable var account = account
        TabView(selection: $selection) {
            ForEach(MainTab.primary) { tab in
                Tab(tab.title, systemImage: tab.systemImage, value: tab) {
                    MainNavigationStack(path: path(for: tab)) { page(for: tab) }
                }
            }
            Tab(MainTab.search.title, systemImage: MainTab.search.systemImage, value: MainTab.search, role: .search) {
                MainNavigationStack(path: path(for: .search)) { SearchView() }
            }
        }
        // 向下浏览时收起标签栏，同时让底部播放器切换到 inline 布局。
        .tabBarMinimizeBehavior(.onScrollDown)
        // 有曲目时在标签栏上方显示迷你播放器，点击打开播放页。
        .tabViewBottomAccessory(isEnabled: player.currentTrack != nil) {
            MiniPlayerView(transitionNamespace: playerTransition) { isNowPlayingPresented = true }
        }
        .tint(DizzyPalette.accent)
        // 「我的」只从各页页头的头像按钮进入，由根视图统一弹出。
        .environment(mine)
        .sheet(isPresented: $mine.isPresented) {
            MineView()
        }
        // 播放页全屏展开：从迷你播放器的封面放大出来，下拉收起。
        .fullScreenCover(isPresented: $isNowPlayingPresented) {
            NowPlayingView()
                .presentationBackground(.clear)
                .navigationTransition(.zoom(sourceID: NowPlayingView.transitionID, in: playerTransition))
        }
        // 音乐库、关注页里的「登录」按钮打开这里。
        .sheet(isPresented: $account.isLoginPresented) {
            NavigationStack {
                LoginView()
                    .toolbar {
                        ToolbarItem(placement: .cancellationAction) {
                            Button(role: .close) { account.isLoginPresented = false }
                        }
                    }
            }
            .preferredColorScheme(.dark)
        }
        // 放在所有 sheet 外层，弹出的页面也能拿到播放器和账号。
        .environment(player)
        .environment(account)
        .environment(offlineLibrary)
        .environment(downloads)
        .environment(services.purchases)
        .environment(\.openRoute, OpenRouteAction { route in
            isNowPlayingPresented = false
            mine.isPresented = false
            paths[selection, default: []].append(route)
        })
        .preferredColorScheme(.dark)
        .onOpenURL { url in
            guard AlipayReturnRouter.isCallback(url) else { return }
            // 回调仅作为唤醒信号，到账仍由当前账号的网站订单核验。
            debugLog("收到支付宝返回，继续核验付款")
            isNowPlayingPresented = false
            mine.isPresented = false
            selection = .library
            paths[.library] = []
            NotificationCenter.default.post(name: .dizzyPaymentReturned, object: nil)
            Task { await services.purchases.check() }
        }
        .onChange(of: scenePhase, initial: true) { _, phase in
            if phase == .background {
                player.saveState()
                services.purchases.pause()
            }
            if phase == .active { Task { await services.purchases.check() } }
        }
        .onReceive(NotificationCenter.default.publisher(for: .dizzyAccountDidChange)) { _ in
            services.purchases.accountDidChange()
            Task { await services.purchases.check() }
        }
    }

    private func path(for tab: MainTab) -> Binding<[AppRoute]> {
        Binding(
            get: { paths[tab] ?? [] },
            set: { paths[tab] = $0 }
        )
    }

    @ViewBuilder
    private func page(for tab: MainTab) -> some View {
        switch tab {
        case .discover: DiscoverView()
        case .labels: LabelsView()
        case .feed: FeedView()
        case .library: LibraryView()
        case .search: SearchView()
        }
    }
}

/// 每个标签页各自的导航栈，统一登记可推入的页面。
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
