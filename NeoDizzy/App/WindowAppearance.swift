import SwiftUI
import UIKit

/// 外观设置作用到窗口：固定浅色或深色时覆盖系统外观，弹窗、菜单和 sheet 一起生效；
/// 窗口的 tintColor 换成当前标签页的主题色，系统提示框的按钮也跟着变。
enum WindowAppearance {
    static func apply(_ settings: AppearanceSettings) {
        let style: UIUserInterfaceStyle = switch settings.mode {
        case .system: .unspecified
        case .light: .light
        case .dark: .dark
        }
        let tint = UIColor(settings.accent.color)
        for case let scene as UIWindowScene in UIApplication.shared.connectedScenes {
            for window in scene.windows {
                window.overrideUserInterfaceStyle = style
                window.tintColor = tint
            }
        }
    }
}
