import AppKit
import Observation

/// 把外观与主题色设置作用到整个 App：NSApp 的外观（窗口、菜单、设置窗口一起生效）和 Dock 图标。
///
/// macOS 没有 iOS 那样的备选图标接口，只能在运行时换 Dock 图片。主题图标由
/// `scripts/generate-app-icon.swift` 用 ictool 渲染好浅色、深色两张，按 App 当前的外观选用；
/// 默认主题且跟随系统时还原为 App 自带的图标，由系统实时切换深浅。
/// 退出后 Dock 和 Finder 里显示的仍是 App 自带的图标。
final class MacAppearanceSync {
    private let settings = AppearanceSettings.shared
    private var appearanceObservation: NSKeyValueObservation?
    private var settingsTask: Task<Void, Never>?

    func start() {
        apply()
        appearanceObservation = NSApp.observe(\.effectiveAppearance) { [weak self] _, _ in
            MainActor.assumeIsolated { self?.updateDockIcon() }
        }
        let settings = settings
        settingsTask = Task { [weak self] in
            for await _ in Observations({ (settings.mode, settings.themeID) }) {
                self?.apply()
            }
        }
    }

    private func apply() {
        NSApp.appearance = switch settings.mode {
        case .system: nil
        case .light: NSAppearance(named: .aqua)
        case .dark: NSAppearance(named: .darkAqua)
        }
        updateDockIcon()
    }

    private func updateDockIcon() {
        let theme = settings.theme
        if theme.id == AppTheme.defaultID && settings.mode == .system {
            NSApp.applicationIconImage = nil
            return
        }
        let isDark = NSApp.effectiveAppearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
        guard let artwork = NSImage(named: "DockIcon-\(theme.id)-\(isDark ? "dark" : "light")") else { return }
        // ictool 的导出图贴满画布；编译后的 icns 在 256 点画布上每侧留 25 点。
        // NSApp 不会替运行时图片补留白，使用同样的比例，换色前后 Dock 尺寸一致。
        let size = NSSize(width: 512, height: 512)
        NSApp.applicationIconImage = NSImage(size: size, flipped: false) { rect in
            artwork.draw(in: rect.insetBy(dx: rect.width * 25 / 256, dy: rect.height * 25 / 256),
                         from: .zero, operation: .sourceOver, fraction: 1)
            return true
        }
    }
}
