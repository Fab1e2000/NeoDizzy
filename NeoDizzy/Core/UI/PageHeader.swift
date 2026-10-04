import SwiftUI

/// 控制「我的」弹层。根视图持有并放进环境，各页页头通过它打开。
@Observable
final class MinePresentation {
    var isPresented = false
}

/// 各主页面共用的页头：左侧大标题，右侧头像玻璃按钮（「我的」的入口）。登录后显示账号头像。
/// 样式沿用 NeoBili；固定、滚动与下拉补偿行为移植自 MeloX_Modified。
struct PageHeader: View {
    let title: String
    @Environment(MinePresentation.self) private var mine: MinePresentation?
    @Environment(AccountStore.self) private var account: AccountStore?

    var body: some View {
        HStack(alignment: .center) {
            Text(title)
                .font(.largeTitle.bold())
                .foregroundStyle(DizzyPalette.text)
                .lineLimit(1)
                .accessibilityAddTraits(.isHeader)
            Spacer(minLength: 16)
            Button { mine?.isPresented = true } label: {
                // 头像是方形的（与社团、用户头像一致），外框用圆角方形而不是圆形。
                avatar
                    .frame(width: 40, height: 40)
                    .clipShape(.rect(cornerRadius: 8))
                    .padding(2)
                    .frame(width: 44, height: 44)
                    .contentShape(.rect(cornerRadius: 10))
                    .background {
                        RoundedRectangle(cornerRadius: 10)
                            .fill(.clear)
                            .glassEffect(.clear.interactive(), in: .rect(cornerRadius: 10))
                    }
            }
            .buttonStyle(.plain)
            .accessibilityLabel("我的")
            .accessibilityHint("打开个人页面")
        }
        .padding(.vertical, 8)
    }

    @ViewBuilder
    private var avatar: some View {
        if let user = account?.account {
            AvatarImage(url: user.avatarURL, size: 40)
        } else {
            Image(systemName: "person.crop.circle.fill")
                .resizable()
                .foregroundStyle(DizzyPalette.mutedText)
        }
    }
}

/// 主页面的骨架：隐藏系统导航栏，页头作为滚动内容的第一行。
/// 内容放在 LazyVStack 里，分页底栏滚到屏幕上时才触发加载。
struct MainTabPage<Content: View>: View {
    let tab: MainTab
    var onRefresh: (() async -> Void)?
    @ViewBuilder var content: Content

    var body: some View {
        let page = ScrollView {
            LazyVStack(alignment: .leading, spacing: 20) {
                ScrollingPageHeaderRow { PageHeader(title: tab.title) }
                content
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 24)
        }
        .pageHeaderPlacement { PageHeader(title: tab.title) }
        .dizzyPageBackground()

        if let onRefresh {
            page.refreshable { await onRefresh() }
        } else {
            page
        }
    }
}

// 移植自 MeloX_Modified（GPLv3）Shared/Components/PageHeader.swift。
// 使用泛型页头，保留 NeoDizzy 的头像入口与水平边距。
enum TitleBarSettings {
    static let storageKey = "pinsPageHeader"
    static let defaultValue = false
}

struct ScrollingPageHeaderRow<Header: View>: View {
    @AppStorage(TitleBarSettings.storageKey) private var pinsTitleBar = TitleBarSettings.defaultValue
    @Environment(\.pageHeaderPull) private var pull
    @ViewBuilder var header: Header

    var body: some View {
        if !pinsTitleBar {
            header.offset(y: -(pull?.distance ?? 0))
                .padding(.bottom, 5)
        }
    }
}

extension View {
    func pageHeaderPlacement<Header: View>(@ViewBuilder header: () -> Header) -> some View {
        modifier(PageHeaderPlacement(header: header()))
    }
}

@MainActor @Observable
final class PageHeaderPull {
    var distance: CGFloat = 0
}

extension EnvironmentValues {
    @Entry var pageHeaderPull: PageHeaderPull? = nil
}

private struct PageHeaderPlacement<Header: View>: ViewModifier {
    let header: Header
    @AppStorage(TitleBarSettings.storageKey) private var pinsTitleBar = TitleBarSettings.defaultValue
    @State private var pull = PageHeaderPull()
    /// 窗口自身的顶部安全区（状态栏、灵动岛），不含导航栏。
    @State private var windowTopInset: CGFloat = 0

    func body(content: Content) -> some View {
        content
            .safeAreaBar(edge: .top, spacing: 0) {
                if pinsTitleBar { header.padding(.horizontal, 20).padding(.bottom, 5) }
            }
            // 页头画在内容里，不需要导航栏让出的空间：忽略整个顶部安全区，只把状态栏的高度加回来，
            // 页头位置与隐藏导航栏时相同。（负的 safeAreaPadding 不会生效。）
            .safeAreaPadding(.top, windowTopInset)
            .ignoresSafeArea(.container, edges: .top)
            .onGeometryChange(for: CGFloat.self) { proxy in
                proxy.size.width
            } action: { _ in
                windowTopInset = UIApplication.shared.connectedScenes
                    .compactMap { ($0 as? UIWindowScene)?.keyWindow?.safeAreaInsets.top }
                    .first ?? 0
            }
            // 导航栏保持显示（透明、无内容），与推入的详情页一致：滑动返回走系统标准过渡，返回按钮原地淡出。
            // 根页隐藏导航栏时，导航栏会作为详情页的一部分随页面滑出，iOS 27.2 在这个过程中丢掉返回按钮的左边距。
            .toolbar(.visible, for: .navigationBar)
            .navigationTitle("")
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(.hidden, for: .navigationBar)
            .scrollEdgeEffectStyle(.soft, for: .top)
            .onScrollGeometryChange(for: CGFloat.self) { geometry in
                max(0, -(geometry.contentOffset.y + geometry.contentInsets.top))
            } action: { _, distance in
                pull.distance = distance
            }
            .environment(\.pageHeaderPull, pull)
    }
}
