import SwiftUI

/// 从播放页等弹出的界面打开某个页面：先收起弹出的界面，再推入当前标签页的导航栈。
struct OpenRouteAction {
    let action: (AppRoute) -> Void

    func callAsFunction(_ route: AppRoute) {
        action(route)
    }
}

extension EnvironmentValues {
    @Entry var openRoute = OpenRouteAction { _ in }
}
