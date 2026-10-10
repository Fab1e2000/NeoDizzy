import SwiftUI

@main
struct NeoDizzyMacApp: App {
    @NSApplicationDelegateAdaptor(MacAppDelegate.self) private var appDelegate

    var body: some Scene {
        // 与 Music 相同只有一个主窗口；关闭后继续播放，从 Dock 或菜单重新打开。
        Window("NeoDizzy", id: SceneID.main) {
            MainWindow()
                .neoDizzyEnvironment(appDelegate.model)
        }
        .defaultSize(width: 1180, height: 780)
        // 每次启动都打开主窗口，不沿用上次退出时窗口已关闭的状态。
        .defaultLaunchBehavior(.presented)
        .windowToolbarStyle(.unified(showsTitle: false))
        // 导航组自行显示图标/文字，避免系统把首个按钮标题再画在整组下方。
        .windowToolbarLabelStyle(fixed: .iconOnly)
        .commands { AppCommands(model: appDelegate.model) }

        Settings {
            SettingsView()
                .neoDizzyEnvironment(appDelegate.model)
        }
    }
}

enum SceneID {
    static let main = "main"
}

extension View {
    /// 每个场景都注入同一份服务与界面状态。
    func neoDizzyEnvironment(_ model: MacAppModel) -> some View {
        let services = model.services
        return self
            .environment(model)
            .environment(model.tabSettings)
            .environment(model.navigation)
            .environment(services.browsingHistory)
            .environment(services.player)
            .environment(services.account)
            .environment(services.offlineLibrary)
            .environment(services.downloads)
            .environment(services.purchases)
            .environment(\.openRoute, OpenRouteAction { model.open($0) })
            .modifier(ThemeTint())
    }
}

/// 在视图的 body 里读主题色，换主题后各场景立即重绘。外观由 `MacAppearanceSync` 设在 NSApp 上。
private struct ThemeTint: ViewModifier {
    func body(content: Content) -> some View {
        content.tint(DizzyPalette.accent)
    }
}
