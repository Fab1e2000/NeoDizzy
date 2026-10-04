import AppKit
import SwiftUI

/// 持有整个 App 共用的服务与界面状态；负责启动恢复、退出保存、Dock 菜单和关闭窗口后继续播放。
final class MacAppDelegate: NSObject, NSApplicationDelegate {
    let model = MacAppModel()
    private var keyMonitor: PlaybackKeyMonitor?
    private var observers: [NSObjectProtocol] = []

    func applicationDidFinishLaunching(_ notification: Notification) {
        Task { await model.services.restore() }
        #if DEBUG
        // 等主窗口建立导航栈后再打开调试页面。
        DispatchQueue.main.asyncAfter(deadline: .now() + 4) { self.applyDebugLaunchArguments() }
        #endif
        keyMonitor = PlaybackKeyMonitor(player: model.player)
        let services = model.services
        // 与 iOS 的 RootView 相同：换账号后重新核验付款。
        observers.append(NotificationCenter.default.addObserver(forName: .dizzyAccountDidChange, object: nil, queue: .main) { _ in
            MainActor.assumeIsolated {
                services.purchases.accountDidChange()
                Task { await services.purchases.check() }
            }
        })
    }

    func applicationDidBecomeActive(_ notification: Notification) {
        Task { await model.services.purchases.check() }
    }

    func applicationWillTerminate(_ notification: Notification) {
        model.player.saveState()
        model.services.purchases.pause()
    }

    /// 与 Music 一致：关闭主窗口后继续播放，点 Dock 图标再打开。
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { false }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        if !flag { model.openMainWindow() }
        return true
    }

    func applicationDockMenu(_ sender: NSApplication) -> NSMenu? {
        let menu = NSMenu()
        menu.autoenablesItems = false
        let player = model.player
        if let track = player.currentTrack {
            let title = NSMenuItem(title: track.title, action: nil, keyEquivalent: "")
            title.isEnabled = false
            menu.addItem(title)
            menu.addItem(.separator())
        }
        menu.addItem(item(player.isPlaying ? "暂停" : "播放", #selector(togglePlayback)))
        menu.addItem(item("下一首", #selector(playNext)))
        menu.addItem(item("上一首", #selector(playPrevious)))
        return menu
    }

    private func item(_ title: String, _ action: Selector) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: "")
        item.target = self
        item.isEnabled = model.player.currentTrack != nil
        return item
    }

    @objc private func togglePlayback() { model.player.togglePlayback() }
    @objc private func playNext() { model.player.next() }
    @objc private func playPrevious() { model.player.previous() }

    #if DEBUG
    /// 仅 Debug：用启动参数打开指定页面，便于脚本截图检查界面，例如
    /// `open NeoDizzy.app --args -debugTab discover -debugRoute disc:KSEP-001 -debugPanel lyrics -debugAppearance dark`。
    private func applyDebugLaunchArguments() {
        let defaults = UserDefaults.standard
        if let appearance = defaults.string(forKey: "debugAppearance") {
            NSApp.appearance = NSAppearance(named: appearance == "dark" ? .darkAqua : .aqua)
        }
        if let tab = defaults.string(forKey: "debugTab") {
            switch tab {
            case "search": model.navigation.selection = .search
            case "history": model.navigation.selection = .history
            default: if let tab = MainTab(rawValue: tab) { model.navigation.selection = .tab(tab) }
            }
        }
        if let query = defaults.string(forKey: "debugSearch") {
            model.search.query = query
            model.submitSearch()
        }
        if let route = defaults.string(forKey: "debugRoute") {
            let parts = route.split(separator: ":", maxSplits: 1).map(String.init)
            switch (parts.first, parts.count > 1 ? parts[1] : nil) {
            case ("disc", let id?): model.navigation.open(.disc(id: id))
            case ("local", let id?): model.navigation.open(.localAlbum(id: id))
            case ("label", let name?): model.navigation.open(.label(name: name))
            case ("tag", let tag?): model.navigation.open(.tag(tag))
            case ("pack", let id?): model.navigation.open(.pack(id: id))
            case ("user", let id?): if let id = Int(id) { model.navigation.open(.user(id: id)) }
            case ("review", let id?): if let id = Int(id) { model.navigation.open(.review(id: id)) }
            default: break
            }
        }
        if let album = defaults.string(forKey: "debugPlayAlbum") {
            Task { try? await model.playAlbum(id: album) }
        }
        let width = defaults.double(forKey: "debugWindowWidth")
        if width > 0, let window = NSApp.windows.first(where: { $0.isVisible && $0.canBecomeMain }) {
            var frame = window.frame
            frame.size.width = width
            window.setFrame(frame, display: true)
        }
        if let panel = defaults.string(forKey: "debugPanel") { model.playerPanel = PlayerPanel(rawValue: panel) }
        // 在本地库与发现之间来回切换，用于 Instruments 测量切换开销。
        let cycles = defaults.integer(forKey: "debugCycleTabs")
        if cycles > 0 {
            Task {
                for index in 0..<cycles * 2 {
                    try? await Task.sleep(for: .milliseconds(1500))
                    model.navigation.selection = .tab(index.isMultiple(of: 2) ? .localLibrary : .discover)
                }
            }
        }
        if defaults.bool(forKey: "debugSettings") { model.openSettings?() }
    }
    #endif
}
