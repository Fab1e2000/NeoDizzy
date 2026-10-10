import SwiftUI

struct RootView: View {
    @State private var selection: MainTab = .discover
    @State private var tabSettings = TabSettings()
    @State private var paymentSheet: PurchaseSheet?
    @State private var mine = MinePresentation()
    @State private var themeIcon = ThemeIconController()
    private let appearance = AppearanceSettings.shared
    let services: AppServices
    private var player: PlayerStore { services.player }
    private var offlineLibrary: OfflineLibraryStore { services.offlineLibrary }
    private var downloads: DownloadStore { services.downloads }
    private var account: AccountStore { services.account }
    @State private var isNowPlayingPresented = false
    @State private var pendingPlayerRoute: AppRoute?
    /// 每个标签页的导航路径。播放页里的「前往专辑」会往当前标签页推入页面。
    @State private var paths: [MainTab: [AppRoute]] = [:]
    @Namespace private var playerTransition
    @Environment(\.scenePhase) private var scenePhase

    init(services: AppServices) {
        self.services = services
        let settings = TabSettings()
        _tabSettings = State(initialValue: settings)
        _selection = State(initialValue: settings.initialTab)
    }

    var body: some View {
        @Bindable var account = account
        TabView(selection: $selection) {
            ForEach(tabSettings.visiblePrimary) { tab in
                Tab(tab.title, systemImage: tab.systemImage, value: tab) {
                    MainNavigationStack(path: path(for: tab)) { page(for: tab) }
                }
            }

        }
        .onChange(of: tabSettings.visibleTabs, initial: true) { _, visible in
            if !visible.contains(selection) { selection = tabSettings.visiblePrimary[0] }
        }
        .sheet(item: $paymentSheet) { sheet in PurchaseView(summary: sheet.summary) }
        // 标签栏与底部播放器始终保持完整布局，不随滚动收缩。
        .tabBarMinimizeBehavior(.never)
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
        .fullScreenCover(isPresented: $isNowPlayingPresented, onDismiss: finishPlayerNavigation) {
            NowPlayingView()
                .presentationBackground(.clear)
                .presentationContentInteraction(.resizes)
                .navigationTransition(.zoom(sourceID: NowPlayingView.transitionID, in: playerTransition))
        }
        // 已购买、关注页里的「登录」按钮打开这里。
        .sheet(isPresented: $account.isLoginPresented) {
            NavigationStack {
                LoginView()
                    .toolbar {
                        ToolbarItem(placement: .cancellationAction) {
                            Button(role: .close) { account.isLoginPresented = false }
                        }
                    }
            }
        }
        // 放在所有 sheet 外层，弹出的页面也能拿到播放器和账号。
        .environment(tabSettings)
        .environment(services.browsingHistory)
        .environment(player)
        .environment(account)
        .environment(offlineLibrary)
        .environment(downloads)
        .environment(services.purchases)
        .environment(themeIcon)
        .environment(\.openRoute, OpenRouteAction { route in
            mine.isPresented = false
            if isNowPlayingPresented {
                pendingPlayerRoute = route
                isNowPlayingPresented = false
            } else {
                paths[selection, default: []].append(route)
            }
        })
        .onOpenURL { url in
            // 从其他 App 的分享菜单「用 NeoDizzy 打开」的歌曲或压缩包，导入音乐文件夹后打开本地库。
            if url.isFileURL {
                mine.isPresented = false
                isNowPlayingPresented = false
                if tabSettings.isVisible(.localLibrary) {
                    selection = .localLibrary
                    paths[.localLibrary] = []
                }
                Task { await offlineLibrary.importItems([url]) }
                return
            }
            guard AlipayReturnRouter.isCallback(url) else { return }
            // 回调仅作为唤醒信号，到账仍由当前账号的网站订单核验。
            debugLog("收到支付宝返回，继续核验付款")
            pendingPlayerRoute = nil
            isNowPlayingPresented = false
            mine.isPresented = false
            if tabSettings.isVisible(.purchased) {
                selection = .purchased
                paths[.purchased] = []
            } else if let pending = services.purchases.current {
                paymentSheet = PurchaseSheet(summary: DiscSummary(id: pending.attempt.discID, title: pending.title, coverURL: nil))
            }
            NotificationCenter.default.post(name: .dizzyPaymentReturned, object: nil)
            Task { await services.purchases.check() }
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
                services.purchases.pause()
            }
            if phase == .active { Task { await services.purchases.check() } }
        }
        .onReceive(NotificationCenter.default.publisher(for: .dizzyAccountDidChange)) { _ in
            services.purchases.accountDidChange()
            Task { await services.purchases.check() }
        }
    }

    // Finish dismissal before pushing the destination.
    private func finishPlayerNavigation() {
        guard let route = pendingPlayerRoute else { return }
        pendingPlayerRoute = nil
        paths[selection, default: []].append(route)
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
        case .shuffle:
            ShuffleView { selection in
                player.playDiscovery(selection)
                isNowPlayingPresented = true
            }
        case .labels: LabelsView()
        case .feed: FeedView()
        case .purchased: PurchasedLibraryView()
        case .localLibrary: LocalLibraryView()
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
