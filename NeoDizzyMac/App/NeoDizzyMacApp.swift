import SwiftUI

@main
struct NeoDizzyMacApp: App {
    @NSApplicationDelegateAdaptor(MacAppDelegate.self) private var appDelegate
    @AppStorage("miniPlayer.floats") private var miniPlayerFloats = true

    var body: some Scene {
        // 与 Music 相同只有一个主窗口；关闭后继续播放，从 Dock 或菜单重新打开。
        Window("NeoDizzy", id: SceneID.main) {
            MainWindow()
                .neoDizzyEnvironment(appDelegate.model)
        }
        .defaultSize(width: 1180, height: 780)
        .windowToolbarStyle(.unified(showsTitle: false))
        .commands { AppCommands(model: appDelegate.model) }

        Window("迷你播放器", id: SceneID.miniPlayer) {
            MiniPlayerWindow()
                .neoDizzyEnvironment(appDelegate.model)
        }
        .windowStyle(.plain)
        .windowResizability(.contentSize)
        .defaultPosition(.bottomTrailing)
        .windowLevel(miniPlayerFloats ? .floating : .normal)
        .windowBackgroundDragBehavior(.enabled)
        .restorationBehavior(.disabled)

        Settings {
            SettingsView()
                .neoDizzyEnvironment(appDelegate.model)
        }
    }
}

enum SceneID {
    static let main = "main"
    static let miniPlayer = "mini-player"
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
            .tint(.dizzyGold)
    }
}
