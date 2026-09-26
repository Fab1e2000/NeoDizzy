import SwiftUI

struct RootView: View {
    @State private var selection: MainTab = .discover
    @State private var mine = MinePresentation()

    var body: some View {
        TabView(selection: $selection) {
            ForEach(MainTab.primary) { tab in
                Tab(tab.title, systemImage: tab.systemImage, value: tab) {
                    MainNavigationStack { page(for: tab) }
                }
            }
            Tab(MainTab.search.title, systemImage: MainTab.search.systemImage, value: MainTab.search, role: .search) {
                MainNavigationStack { SearchView() }
            }
        }
        .tint(DizzyPalette.accent)
        // 「我的」只从各页页头的头像按钮进入，由根视图统一弹出。
        .environment(mine)
        .sheet(isPresented: $mine.isPresented) {
            MineView()
        }
        .preferredColorScheme(.dark)
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
    @ViewBuilder var root: Root

    var body: some View {
        NavigationStack {
            root.navigationDestination(for: AppRoute.self) { route in
                AppRouteDestination(route: route)
            }
        }
    }
}
