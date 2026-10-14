import SwiftUI

/// 全局设置由宿主持有，平台账号弹层由模块自己管理。
@Observable
final class AppSettingsPresentation {
    var isPresented = false
}

/// 设置入口在所有模块中一致；只有提供账号能力的模块才显示头像。
struct PageHeader: View {
    let title: String
    @Environment(AppSettingsPresentation.self) private var settings: AppSettingsPresentation?
    @Environment(ModuleRegistry.self) private var modules: ModuleRegistry?
    @Environment(ModuleHost.self) private var host: ModuleHost?

    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            Text(title)
                .font(.largeTitle.bold())
                .foregroundStyle(DizzyPalette.text)
                .lineLimit(1)
                .accessibilityAddTraits(.isHeader)
            Spacer(minLength: 8)
            headerActions
        }
        .padding(.vertical, 8)
    }

    private var accountEntry: ModuleAccountEntry? {
        guard let host else { return nil }
        return modules?.accountEntry(for: host.selection)
    }

    // MeloX ContentView.primaryToolbar groups trailing actions in one system glass surface.
    // This custom page header uses the same grouping while keeping account and settings separate.
    private var headerActions: some View {
        HStack(spacing: 0) {
            if let entry = accountEntry, let host {
                Button { modules?.openAccount(for: host.selection) } label: {
                    Group {
                        if let url = entry.avatarURL {
                            AvatarImage(url: url, size: 28)
                        } else {
                            Image(systemName: "person.crop.circle.fill")
                                .resizable()
                                .foregroundStyle(DizzyPalette.mutedText)
                        }
                    }
                    .frame(width: 28, height: 28)
                    .clipShape(.circle)
                    .frame(width: 44, height: 44)
                    .contentShape(.rect)
                }
                .accessibilityLabel(entry.title)
            }
            Button { settings?.isPresented = true } label: {
                Image(systemName: "gearshape")
                    .font(.title2)
                    .foregroundStyle(DizzyPalette.text)
                    .frame(width: 44, height: 44)
                    .contentShape(.rect)
            }
            .accessibilityLabel("设置")
            .accessibilityHint("打开应用全局设置")
        }
        .buttonStyle(.plain)
        .padding(.horizontal, accountEntry == nil ? 0 : 4)
        .glassEffect(.regular.interactive(), in: .capsule)
        .accessibilityElement(children: .contain)
    }

}

/// 主页面的骨架：隐藏系统导航栏，页头作为滚动内容的第一行。
/// 内容放在 LazyVStack 里，分页底栏滚到屏幕上时才触发加载。
struct MainTabPage<Content: View>: View {
    let title: String
    var onRefresh: (() async -> Void)?
    @ViewBuilder var content: Content

    var body: some View {
        let page = ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                ScrollingPageHeaderRow { PageHeader(title: title) }
                LazyVStack(alignment: .leading, spacing: 20) { content }
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 24)
        }
        .pageHeaderPlacement { PageHeader(title: title) }
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
    @ViewBuilder var header: Header

    var body: some View {
        if !pinsTitleBar {
            header
                .padding(.bottom, 5)
        }
    }
}

extension View {
    func pageHeaderPlacement<Header: View>(@ViewBuilder header: () -> Header) -> some View {
        modifier(PageHeaderPlacement(header: header()))
    }
}

private struct PageHeaderPlacement<Header: View>: ViewModifier {
    let header: Header
    @AppStorage(TitleBarSettings.storageKey) private var pinsTitleBar = TitleBarSettings.defaultValue
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

    }
}
