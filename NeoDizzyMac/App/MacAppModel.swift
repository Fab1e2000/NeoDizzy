import SwiftUI

/// 侧边栏的一项。主页面沿用 iOS 的 `MainTab`（顺序、隐藏和启动页面共用 `TabSettings`），
/// 另外加上 Mac 侧边栏才有的搜索、浏览记录与下载。
enum SidebarItem: Hashable {
    case search
    case tab(MainTab)
    case history
    case downloads

    var title: String {
        switch self {
        case .search: String(localized: "搜索")
        case .tab(let tab): tab.title
        case .history: String(localized: "最近浏览")
        case .downloads: String(localized: "下载")
        }
    }

    var systemImage: String {
        switch self {
        case .search: "magnifyingglass"
        case .tab(let tab):
            switch tab {
            case .discover: "square.grid.2x2"
            case .shuffle: "shuffle"
            case .labels: "music.mic"
            case .feed: "newspaper"
            case .purchased: "bag"
            case .localLibrary: "square.stack"
            }
        case .history: "clock"
        case .downloads: "arrow.down.circle"
        }
    }

    /// 侧边栏分组：DizzyLab 在线内容与本机资料库。
    static let onlineTabs: Set<MainTab> = [.discover, .shuffle, .labels, .feed]
}

/// 右侧检查器显示的内容，与 Music 的歌词 / 待播清单面板相同。
enum PlayerPanel: String, Hashable {
    case lyrics, queue
}

/// 主窗口的导航状态：侧边栏选中项，以及每一项各自的导航路径。
@Observable
final class NavigationModel {
    var selection: SidebarItem?
    private(set) var paths: [SidebarItem: [AppRoute]] = [:]

    init(selection: SidebarItem) {
        self.selection = selection
    }

    func path(for item: SidebarItem) -> [AppRoute] { paths[item] ?? [] }

    func setPath(_ path: [AppRoute], for item: SidebarItem) { paths[item] = path }

    /// 推入当前侧边栏项的导航栈。
    func open(_ route: AppRoute) {
        let item = selection ?? .tab(.discover)
        if selection == nil { selection = item }
        guard paths[item]?.last != route else { return }
        paths[item, default: []].append(route)
    }

    /// 回到某一项的根页面（再次点击侧边栏同一项时）。
    func popToRoot(_ item: SidebarItem) { paths[item] = [] }
}

/// 当前页面的刷新动作（⌘R）。页面出现时登记，消失时撤销，推入的页面会覆盖其下的根页面。
struct PageRefresh {
    let id: UUID
    let action: () async -> Void
}

/// Mac 版的全局界面状态。由 AppDelegate 持有一次，主窗口、迷你播放器、设置和菜单共用。
@Observable
final class MacAppModel {
    let services: AppServices
    let tabSettings = TabSettings()
    let navigation: NavigationModel
    let search = SearchModel()

    // 根页面的数据跨侧边栏切换保留，与 iOS 标签页常驻的效果一致。
    let discover = DiscoverModel()
    let feed = FeedModel()
    let library = LibraryModel()
    let labels = PagedList { page in try await DizzyAPI.shared.labels(page: page) }

    var playerPanel: PlayerPanel?
    var isFullScreenPlayerPresented = false
    var isDisclaimerPresented = false
    var purchaseTarget: DiscSummary?
    var isSearchFocused = false
    private(set) var refresh: PageRefresh?
    /// 由窗口登记的 openWindow 动作，用来在主窗口被关闭后从 Dock、全屏播放器或迷你播放器重新打开它。
    @ObservationIgnored var openWindow: ((String) -> Void)?
    @ObservationIgnored var openSettings: (() -> Void)?

    var player: PlayerStore { services.player }
    var account: AccountStore { services.account }

    init() {
        services = AppServices()
        navigation = NavigationModel(selection: .tab(TabSettings().initialTab))
    }

    func openMainWindow() { openWindow?(SceneID.main) }

    func registerRefresh(_ refresh: PageRefresh) { self.refresh = refresh }

    func unregisterRefresh(_ id: UUID) {
        if refresh?.id == id { refresh = nil }
    }

    /// 打开某个页面：从迷你播放器、全屏播放器或菜单调用时先回到主窗口。
    func open(_ route: AppRoute) {
        isFullScreenPlayerPresented = false
        openMainWindow()
        navigation.open(route)
    }

    /// 当前曲目所在的专辑页面。
    var currentAlbumRoute: AppRoute? {
        guard let track = player.currentTrack else { return nil }
        if let local = track.localSource { return .localAlbum(id: local.albumID) }
        return track.discID.isEmpty ? nil : .disc(id: track.discID)
    }

    func togglePanel(_ panel: PlayerPanel) {
        playerPanel = playerPanel == panel ? nil : panel
    }

    func showSearch() {
        openMainWindow()
        navigation.selection = .search
        isSearchFocused = true
    }

    func submitSearch() {
        search.submit()
        if search.keyword != nil { navigation.selection = .search }
    }

    /// 按专辑 ID 拉取详情后从第一首开始播放（网格卡片上的悬停播放按钮）。
    func playAlbum(id: String, shuffled: Bool = false) async throws {
        if let album = services.offlineLibrary.album(id: id) {
            play(album.tracks, shuffled: shuffled)
            return
        }
        let detail = try await DizzyAPI.shared.discDetail(id: id)
        play(detail.tracks, streams: detail.streams, shuffled: shuffled)
    }

    func play(_ tracks: [Track], streams: [String: URL] = [:], shuffled: Bool = false) {
        guard !tracks.isEmpty else { return }
        player.play(tracks, startAt: shuffled ? Int.random(in: tracks.indices) : 0, streams: streams)
        if player.isShuffled != shuffled { player.toggleShuffle() }
    }

    func playDiscovery(_ selection: ShuffleTrack) {
        player.playDiscovery(selection)
    }

    func changeVolume(by delta: Float) {
        player.volume = min(max(player.volume + delta, 0), 1)
    }
}

extension Color {
    /// DizzyLab 金色。显式使用资源里的颜色，不随系统强调色变化；浅色外观自动换成更深的金色。
    static let dizzyGold = Color("AccentColor")
}

extension Bundle {
    var versionText: String {
        let version = infoDictionary?["CFBundleShortVersionString"] as? String ?? "?"
        let build = infoDictionary?["CFBundleVersion"] as? String ?? "?"
        return "\(version) (\(build))"
    }
}
