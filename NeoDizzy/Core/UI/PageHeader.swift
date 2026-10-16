import SwiftUI

/// 全局设置由宿主持有，平台账号弹层由模块自己管理。
@Observable
final class AppSettingsPresentation {
    var isPresented = false
    /// 在设置里点了某个平台的账号：设置收起后再打开这个模块的登录或账号页。
    var pendingAccount: ModuleID?
}

/// A page-owned action grouped with the shared header controls.
struct PageHeaderAction {
    let title: String
    let systemImage: String
    var badge: Int = 0
    let perform: () -> Void
}

/// A module's own search, shown as the system search field under the large title.
struct PageSearch {
    var text: Binding<String>
    var prompt: String
    var submit: () -> Void
}

/// 根页面使用系统大标题导航栏：上滑时大标题和搜索框一起收起，变成居中的小标题。
/// 右上角只有设置入口（加上页面自己的操作）；各平台的登录在设置里。
struct RootPageChrome: ViewModifier {
    let title: String
    var action: PageHeaderAction?
    var search: PageSearch?
    @Environment(AppSettingsPresentation.self) private var settings: AppSettingsPresentation?

    func body(content: Content) -> some View {
        let page = content
            .navigationTitle(title)
            .navigationBarTitleDisplayMode(.large)
            .toolbar { toolbar }
        if let search {
            page
                // 搜索框始终展开在标题下方，不用先下拉才出现。
                .searchable(text: search.text, placement: .navigationBarDrawer(displayMode: .always),
                            prompt: Text(search.prompt))
                .onSubmit(of: .search, search.submit)
        } else {
            page
        }
    }

    @ToolbarContentBuilder private var toolbar: some ToolbarContent {
        if let action {
            ToolbarItem(placement: .topBarTrailing) {
                Button(action: action.perform) {
                    Image(systemName: action.systemImage)
                        .overlay(alignment: .topTrailing) {
                            if action.badge > 0 {
                                Text("\(action.badge)")
                                    .font(.caption2.weight(.bold))
                                    .monospacedDigit()
                                    .foregroundStyle(DizzyPalette.onAccent)
                                    .padding(.horizontal, 4)
                                    .frame(minWidth: 16, minHeight: 16)
                                    .background(DizzyPalette.accentFill, in: .capsule)
                                    .offset(x: 8, y: -6)
                            }
                        }
                }
                .accessibilityLabel(action.title)
                .accessibilityValue(action.badge > 0 ? "\(action.badge) 项进行中" : "")
            }
        }
        ToolbarItem(placement: .topBarTrailing) {
            Button("设置", systemImage: "gearshape") { settings?.isPresented = true }
                .accessibilityHint("打开应用全局设置")
        }
    }
}

extension View {
    func rootPageChrome(title: String, action: PageHeaderAction? = nil, search: PageSearch? = nil) -> some View {
        modifier(RootPageChrome(title: title, action: action, search: search))
    }
}

/// 主页面的骨架：系统大标题 + 模块自己的搜索框，内容放在 LazyVStack 里，分页底栏滚到屏幕上时才触发加载。
struct MainTabPage<Content: View>: View {
    let title: String
    var search: PageSearch? = nil
    var onRefresh: (() async -> Void)?
    var headerAction: PageHeaderAction? = nil
    @ViewBuilder var content: Content

    var body: some View {
        let page = ScrollView {
            LazyVStack(alignment: .leading, spacing: 20) { content }
                .padding(.horizontal, 20)
                .padding(.top, 8)
                .padding(.bottom, 24)
        }
        .dizzyPageBackground()
        .rootPageChrome(title: title, action: headerAction, search: search)

        if let onRefresh {
            page.refreshable { await onRefresh() }
        } else {
            page
        }
    }
}
