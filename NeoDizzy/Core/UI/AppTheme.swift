import Observation
import SwiftUI
#if os(macOS)
import AppKit
#else
import UIKit
#endif

/// 一个来源的主题色：每个标签页用自己来源的颜色，资料库、搜索等不属于某个来源的页面用黑色（深色外观下为白色）。
///
/// 每种颜色有深浅两档：浅色外观用较深的一档，白底上才看得清；深色外观用明亮的一档。
/// 颜色由各平台在 `ModuleDescriptor` 里登记，基座只认识中性的 `neutral`。
struct AccentPalette: Equatable, Sendable {
    /// 浅色外观里的文字、图标颜色。
    let light: UInt32
    /// 深色外观里的文字、图标颜色，也用在深色底上（播放页等）。
    let dark: UInt32
    /// 实底（卡片、角标、主要按钮）；默认与文字同色。
    var lightFill: UInt32? = nil
    var darkFill: UInt32? = nil
    /// 实底上的文字和图标；默认白色。底色太浅、白字看不清时换成同色系的深色。
    var lightInk: UInt32? = nil
    var darkInk: UInt32? = nil

    /// 不属于任何来源的页面：浅色外观为黑色，深色外观为白色。
    static let neutral = AccentPalette(light: 0x000000, dark: 0xFFFFFF, darkInk: 0x000000)

    var color: Color { .adaptive(light: light, dark: dark) }

    /// 主题色铺满的实底：卡片、角标、主要按钮。
    var fill: Color { .adaptive(light: lightFill ?? light, dark: darkFill ?? dark) }

    /// 实底上的文字和图标。
    var onFill: Color { .adaptive(light: lightInk ?? 0xFFFFFF, dark: darkInk ?? 0xFFFFFF) }
}

/// 界面外观：跟随系统，或固定浅色、深色。
enum AppAppearance: String, CaseIterable, Identifiable {
    case system, light, dark

    var id: Self { self }

    var title: String {
        switch self {
        case .system: "跟随系统"
        case .light: "浅色"
        case .dark: "深色"
        }
    }

    var colorScheme: ColorScheme? {
        switch self {
        case .system: nil
        case .light: .light
        case .dark: .dark
        }
    }
}

/// 外观设置存进 UserDefaults；主题色跟随当前标签页的来源，不保存。
///
/// `DizzyPalette.accent` 直接读这里，视图在 body 里用到主题色就会被 Observation 记录，
/// 切换标签页后自动刷新，不需要每个页面单独注入环境值。
@Observable
final class AppearanceSettings {
    static let shared = AppearanceSettings()
    static let modeKey = "appearance.mode"

    var mode: AppAppearance {
        didSet { defaults.set(mode.rawValue, forKey: Self.modeKey) }
    }

    /// 当前标签页来源的主题色，由宿主在切换标签页时设置。
    var accent: AccentPalette = .neutral

    @ObservationIgnored private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        mode = defaults.string(forKey: Self.modeKey).flatMap(AppAppearance.init(rawValue:)) ?? .system
    }
}

extension Color {
    /// 随浅色、深色外观自动切换的颜色。
    nonisolated static func adaptive(light: UInt32, dark: UInt32) -> Color {
        #if os(macOS)
        Color(nsColor: NSColor(name: nil) { appearance in
            NSColor(hex: appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua ? dark : light)
        })
        #else
        Color(uiColor: UIColor { traits in
            UIColor(hex: traits.userInterfaceStyle == .dark ? dark : light)
        })
        #endif
    }
}

#if os(macOS)
private extension NSColor {
    nonisolated convenience init(hex: UInt32) {
        self.init(srgbRed: CGFloat((hex >> 16) & 0xFF) / 255, green: CGFloat((hex >> 8) & 0xFF) / 255,
                  blue: CGFloat(hex & 0xFF) / 255, alpha: 1)
    }
}
#else
private extension UIColor {
    nonisolated convenience init(hex: UInt32) {
        self.init(red: CGFloat((hex >> 16) & 0xFF) / 255, green: CGFloat((hex >> 8) & 0xFF) / 255,
                  blue: CGFloat(hex & 0xFF) / 255, alpha: 1)
    }
}
#endif
