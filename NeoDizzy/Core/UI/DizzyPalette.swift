import SwiftUI

/// 配色取自 DizzyLab 官网（Bootstrap 主题变量和 dizzz.css）。整个 App 固定深色。
enum DizzyPalette {
    /// 官网 `--primary` / `theme-color`，页面底色。
    static let background = Color(hex: 0x1A1A1A)
    /// 卡片和列表行。官网卡片与底色相同，App 里略微提亮以区分层级。
    static let surface = Color(hex: 0x262626)
    static let text = Color(hex: 0xFFFFFF)
    /// 官网 `.text-muted`。
    static let mutedText = Color(hex: 0x919AA1)
    /// 官网 `--warning`：「现在购买」按钮和价格。
    static let accent = Color(hex: 0xF0AD4E)
    /// 官网 `--success`：免费。
    static let success = Color(hex: 0x4BBF73)
    /// 官网 `--info`：标签、兑换。
    static let info = Color(hex: 0x1F9BCF)
    /// 官网 `--danger`。
    static let danger = Color(hex: 0xD9534F)
    /// 官网「已有数字版，下载」按钮。
    static let download = Color(hex: 0x64B5FF)
    #if os(macOS)
    /// Mac 版跟随系统外观，封面占位使用系统的浅灰填充。
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
