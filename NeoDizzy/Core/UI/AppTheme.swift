import Observation
import SwiftUI
#if os(macOS)
import AppKit
#else
import UIKit
#endif

/// 主题色：替换界面里原来固定的 DizzyLab 金色，桌面图标同步换成同色版本。
///
/// 每个主题有深浅两档：深色外观用明亮的一档，浅色外观换成更深的一档，白底上才看得清。
/// 图标由 `scripts/generate-app-icon.swift` 按这张表生成，增删主题后需重新运行脚本。
struct AppTheme: Identifiable, Equatable {
    static let defaultID = "gold"
    let id: String
    let name: String
    /// 深色外观的颜色，也是深色图标里字母的颜色。
    let dark: UInt32
    /// 浅色外观的颜色，也是浅色图标里字母的颜色。
    let light: UInt32

    static let presets: [AppTheme] = [
        .init(id: "gold", name: "鎏金", dark: 0xF0AD4E, light: 0xC4851C),
        .init(id: "orange", name: "橘橙", dark: 0xFF8F4D, light: 0xD9622B),
        .init(id: "coral", name: "珊瑚红", dark: 0xF26B5E, light: 0xD2463A),
        .init(id: "pink", name: "樱花粉", dark: 0xF27BAE, light: 0xD2508C),
        .init(id: "violet", name: "紫罗兰", dark: 0xA98BF5, light: 0x7656D6),
        .init(id: "blue", name: "天青蓝", dark: 0x4FB3F0, light: 0x1F7FC4),
        .init(id: "teal", name: "青瓷", dark: 0x3CC4B4, light: 0x16917F),
        .init(id: "green", name: "青草绿", dark: 0x5CCB7E, light: 0x2E9A55),
        .init(id: "cocoa", name: "可可棕", dark: 0xC9A07F, light: 0x8F6447),
        .init(id: "graphite", name: "石墨灰", dark: 0xAEB4BC, light: 0x5F6670),
    ]

    static func selected(_ id: String) -> AppTheme {
        presets.first { $0.id == id } ?? presets[0]
    }

    /// 对应的 Icon Composer 图标；默认主题就是主图标。
    var iconName: String { id == Self.defaultID ? "NeoDizzyIcon" : "NeoDizzyIcon-\(id)" }

    var color: Color { .adaptive(light: light, dark: dark) }

    /// 铺在主题色上的文字和图标：按对比度在黑白之间选，浅色主题配黑字，深色主题配白字。
    var onColor: Color { .adaptive(light: Self.contrastingInk(on: light), dark: Self.contrastingInk(on: dark)) }

    private static func contrastingInk(on hex: UInt32) -> UInt32 {
        func channel(_ shift: UInt32) -> Double {
            let value = Double((hex >> shift) & 0xFF) / 255
            return value <= 0.04045 ? value / 12.92 : pow((value + 0.055) / 1.055, 2.4)
        }
        let luminance = 0.2126 * channel(16) + 0.7152 * channel(8) + 0.0722 * channel(0)
        // 与黑字、白字的对比度相等处约为 0.179。
        return luminance > 0.179 ? 0x000000 : 0xFFFFFF
    }
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

/// 外观与主题色设置，存进 UserDefaults。
///
/// `DizzyPalette.accent` 直接读这里，视图在 body 里用到主题色就会被 Observation 记录，
/// 换主题后自动刷新，不需要每个页面单独注入环境值。
@Observable
final class AppearanceSettings {
    static let shared = AppearanceSettings()
    static let themeKey = "appearance.theme"
    static let modeKey = "appearance.mode"
    static let albumDimmingKey = "appearance.albumDimming"
    static let defaultAlbumDimming = 5

    var themeID: String {
        didSet { defaults.set(themeID, forKey: Self.themeKey) }
    }

    var mode: AppAppearance {
        didSet { defaults.set(mode.rawValue, forKey: Self.modeKey) }
    }

    /// 专辑页封面取色背景上叠的黑（深色）或白（浅色）的不透明度，0–100。
    var albumDimming: Int {
        didSet {
            let clamped = min(max(albumDimming, 0), 100)
            if clamped != albumDimming { albumDimming = clamped }
            defaults.set(clamped, forKey: Self.albumDimmingKey)
        }
    }

    var theme: AppTheme { .selected(themeID) }

    @ObservationIgnored private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        themeID = AppTheme.selected(defaults.string(forKey: Self.themeKey) ?? AppTheme.defaultID).id
        mode = defaults.string(forKey: Self.modeKey).flatMap(AppAppearance.init(rawValue:)) ?? .system
        albumDimming = (defaults.object(forKey: Self.albumDimmingKey) as? Int).map { min(max($0, 0), 100) }
            ?? Self.defaultAlbumDimming
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
