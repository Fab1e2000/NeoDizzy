import SwiftUI

/// 配色取自 DizzyLab 官网（Bootstrap 主题变量和 dizzz.css）。官网只有深色，
/// 浅色外观的颜色按同样的层级另配，并把彩色调深，在白底上保持可读。
enum DizzyPalette {
    /// 官网 `--primary` / `theme-color`，页面底色。
    static let background = Color.adaptive(light: 0xF2F2F4, dark: 0x1A1A1A)
    /// 卡片和列表行。官网卡片与底色相同，App 里略微提亮以区分层级。
    static let surface = Color.adaptive(light: 0xFFFFFF, dark: 0x262626)
    static let text = Color.adaptive(light: 0x1A1A1A, dark: 0xFFFFFF)
    /// 官网 `.text-muted`。
    static let mutedText = Color.adaptive(light: 0x6A737B, dark: 0x919AA1)
    /// 主题色。默认是官网 `--warning` 的金色：「现在购买」按钮和价格。
    static var accent: Color { AppearanceSettings.shared.theme.color }
    /// 铺在主题色上的文字和图标。
    static var onAccent: Color { AppearanceSettings.shared.theme.onColor }
    /// 深色底上的主题色（封面上的半透明黑角标等），浅色外观下也用明亮的一档。
    static var accentOnDark: Color { Color(hex: AppearanceSettings.shared.theme.dark) }
    /// 官网 `--success`：免费。
    static let success = Color.adaptive(light: 0x2E9A55, dark: 0x4BBF73)
    /// 官网 `--info`：标签、兑换。
    static let info = Color.adaptive(light: 0x1A84B3, dark: 0x1F9BCF)
    /// 官网 `--danger`。
    static let danger = Color.adaptive(light: 0xC9302C, dark: 0xD9534F)
    /// 官网「已有数字版，下载」按钮。
    static let download = Color.adaptive(light: 0x1E7FD8, dark: 0x64B5FF)
    #if os(macOS)
    /// Mac 版使用系统的浅灰填充作封面占位。
    static let artworkPlaceholder = Color(nsColor: .quaternaryLabelColor)
    static let artworkPlaceholderSymbol = Color(nsColor: .tertiaryLabelColor)
    #else
    static let artworkPlaceholder = surface
    static let artworkPlaceholderSymbol = mutedText
    #endif
}

extension Color {
    init(hex: UInt32, opacity: Double = 1) {
        self.init(
            .sRGB,
            red: Double((hex >> 16) & 0xFF) / 255,
            green: Double((hex >> 8) & 0xFF) / 255,
            blue: Double(hex & 0xFF) / 255,
            opacity: opacity
        )
    }
}

extension View {
    /// 主页面和推入页面共用的底色，铺满安全区。
    func dizzyPageBackground() -> some View {
        background(DizzyPalette.background.ignoresSafeArea())
    }
}
