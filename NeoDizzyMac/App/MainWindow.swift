import SwiftUI

/// 主窗口：侧边栏、内容区、底部浮动播放条和右侧歌词 / 待播清单面板，布局参考 macOS 的 Music。
struct MainWindow: View {
    @Environment(MacAppModel.self) private var model
    @Environment(AccountStore.self) private var account
    @Environment(\.openWindow) private var openWindow
    @Environment(\.openSettings) private var openSettings
    @FocusState private var isSearchFocused: Bool

    var body: some View {
        @Bindable var model = model
        @Bindable var account = account
        @Bindable var search = model.search
        NavigationSplitView {
            SidebarView()
                .navigationSplitViewColumnWidth(min: 190, ideal: 220, max: 300)
        } detail: {
            DetailColumn()
        }
        .searchable(text: $search.query, placement: .sidebar, prompt: "专辑、社团或用户")
        .searchFocused($isSearchFocused)
        .onSubmit(of: .search) { model.submitSearch() }
        // 面板挂在分栏视图上：放在导航栈里的页面上时，根页面与推入页面会同时声明面板。
        .inspector(isPresented: panelPresented) {
            PlayerInspector()
                .inspectorColumnWidth(min: 280, ideal: 330, max: 460)
        }
        .onChange(of: search.query) { _, query in
            if query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { search.clear() }
        }
        .onChange(of: model.isSearchFocused) { _, focused in
            if focused { isSearchFocused = true; model.isSearchFocused = false }
        }
        .sheet(item: $model.purchaseTarget) { PurchaseSheet(summary: $0) }
        .sheet(isPresented: $account.isLoginPresented) { LoginSheet() }
        .sheet(isPresented: $model.isDisclaimerPresented) { DisclaimerSheet() }
        .frame(minWidth: 860, minHeight: 580)
        .onAppear {
            let openWindow = openWindow, openSettings = openSettings
            model.openWindow = { openWindow(id: $0) }
            model.openSettings = { openSettings() }
        }
    }

    private var panelPresented: Binding<Bool> {
        Binding(get: { model.playerPanel != nil },
                set: { if !$0 { model.playerPanel = nil } })
    }
}

/// 侧边栏：顶部搜索，「DizzyLab」在线内容与「资料库」两组。
struct SidebarView: View {
    @Environment(MacAppModel.self) private var model
    @Environment(TabSettings.self) private var tabs
    @Environment(DownloadStore.self) private var downloads
    @Environment(\.openSettings) private var openSettings

    private var onlineTabs: [MainTab] { tabs.visiblePrimary.filter { SidebarItem.onlineTabs.contains($0) } }
    private var libraryTabs: [MainTab] { tabs.visiblePrimary.filter { !SidebarItem.onlineTabs.contains($0) } }
    private var activeDownloads: Int { downloads.jobs.filter(\.isActive).count }

    var body: some View {
        @Bindable var navigation = model.navigation
        List(selection: $navigation.selection) {
            row(.search)
            if !onlineTabs.isEmpty {
                Section("DizzyLab") {
                    ForEach(onlineTabs) { row(.tab($0)) }
                }
            }
            Section("资料库") {
                ForEach(libraryTabs) { row(.tab($0)) }
                row(.history)
                row(.downloads)
                    .badge(activeDownloads)
            }
        }
        .listStyle(.sidebar)
        .contextMenu(forSelectionType: SidebarItem.self) { items in
            if case .tab(let tab)? = items.first, items.count == 1 {
                Button("从边栏隐藏「\(tab.title)」") { tabs.setVisible(false, for: tab) }
                    .disabled(!tabs.canHide(tab))
            }
            Button("编辑边栏…") { openSettings() }
        }
        .onChange(of: tabs.visibleTabs) { _, visible in
            if case .tab(let tab)? = navigation.selection, !visible.contains(tab) {
                navigation.selection = visible.first.map(SidebarItem.tab) ?? .search
            }
        }
    }

    private func row(_ item: SidebarItem) -> some View {
        Label(item.title, systemImage: item.systemImage)
            .tag(item)
    }
}

/// 内容区：每个侧边栏项一个导航栈，路径保存在 `NavigationModel` 里，切换后再回来仍停在原页面。
struct DetailColumn: View {
    @Environment(MacAppModel.self) private var model

    var body: some View {
        let navigation = model.navigation
        let item = navigation.selection ?? .tab(.discover)
        NavigationStack(path: Binding(get: { navigation.path(for: item) }, set: { navigation.setPath($0, for: item) })) {
            RootPage(item: item)
                .detailChrome()
                .navigationDestination(for: AppRoute.self) { RouteDestination(route: $0).detailChrome() }
        }
        .id(item)
    }
}

private struct RootPage: View {
    let item: SidebarItem

    var body: some View {
        switch item {
        case .search: SearchPage()
        case .tab(.discover): DiscoverPage()
        case .tab(.shuffle): ShufflePage()
        case .tab(.labels): LabelsPage()
        case .tab(.feed): FeedPage()
        case .tab(.purchased): PurchasedPage()
        case .tab(.localLibrary): LocalLibraryPage()
        case .history: HistoryPage()
        case .downloads: DownloadsPage()
        }
    }
}

/// 导航栈里可以推入的页面，对应 iOS 的 AppRouteDestination。
struct RouteDestination: View {
    let route: AppRoute

    var body: some View {
        switch route {
        case .disc(let id): AlbumPage(id: id)
        case .localAlbum(let id): LocalAlbumPage(id: id)
        case .label(let name): LabelDetailPage(name: name)
        case .user(let id): UserPage(userID: id)
        case .tag(let tag): TagPage(tag: tag)
        case .pack(let id): PackPage(id: id)
        case .review(let id): ReviewPage(id: id)
        }
    }
}

extension View {
    /// 内容区每个页面共有的底部播放条和工具栏账户按钮。
    /// 挂在导航栈内的每个页面上：macOS 推入页面时会替换整个详情栏，栈外的修饰符不会保留。
    func detailChrome() -> some View {
        modifier(DetailChrome())
    }

    /// 登记当前页面的刷新动作，供「显示 → 刷新」（⌘R）调用。
    func pageRefresh(_ action: @escaping () async -> Void) -> some View {
        modifier(PageRefreshModifier(action: action))
    }
}

private struct PageRefreshModifier: ViewModifier {
    @Environment(MacAppModel.self) private var model
    @State private var id = UUID()
    let action: () async -> Void

    func body(content: Content) -> some View {
        content
            .onAppear { model.registerRefresh(PageRefresh(id: id, action: action)) }
            .onDisappear { model.unregisterRefresh(id) }
    }
}

/// 底部播放条和工具栏账户按钮。
private struct DetailChrome: ViewModifier {
    @Environment(MacAppModel.self) private var model

    func body(content: Content) -> some View {
        content
            .safeAreaInset(edge: .bottom, spacing: 0) {
                PlayerBar()
                    .padding(.horizontal, 16)
                    .padding(.bottom, 14)
            }
            .toolbar {
                // 没有居中控件的页面里，工具栏按钮默认紧跟返回按钮；用弹性空白把它们推到右侧。
                ToolbarSpacer(.flexible)
                ToolbarItem(placement: .automatic) { AccountMenu() }
            }
    }
}
