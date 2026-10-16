import SwiftUI

/// 没有独立路由、由当前页面带着数据打开的子页面（「全部作品」「查看全部」、设置里的二级页等）。
/// 用它代替 `NavigationLink { 页面 }`：页面也进入导航路径，在里面再点进详情时只推入一页。
/// 按 ID 比较，每次点击都是一个新页面。
struct InlinePageRoute: Hashable {
    let id = UUID()
    let make: @MainActor () -> AnyView

    static func == (lhs: Self, rhs: Self) -> Bool { lhs.id == rhs.id }
    func hash(into hasher: inout Hasher) { hasher.combine(id) }
}

extension ModuleID {
    static let inlinePage = ModuleID(rawValue: "inlinePage")
}

extension AppRoute {
    static func page<Content: View>(_ title: String = "", @ViewBuilder _ content: @escaping @MainActor () -> Content) -> Self {
        Self(moduleID: .inlinePage, destination: InlinePageRoute { AnyView(content()) }, title: title)
    }
}
