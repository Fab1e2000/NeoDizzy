// 移植自 NeoBili Core/UI/ThemeIconController.swift。
import Observation
import SwiftUI
import UIKit

/// 桌面图标跟随主题色。每个主题的图标都带浅色、深色两版，由系统按主屏幕外观切换。
/// UIKit 不接受重叠的请求，所以换图标的请求逐个提交。
@Observable
final class ThemeIconController {
    private(set) var errorMessage: String?
    private var requestedIconName: String?
    private var isUpdating = false

    func apply(theme: AppTheme) async {
        requestedIconName = theme.id == AppTheme.defaultID ? nil : theme.iconName
        guard !isUpdating else { return }
        guard UIApplication.shared.supportsAlternateIcons else {
            errorMessage = "当前系统不支持切换桌面图标。"
            return
        }
        isUpdating = true
        defer { isUpdating = false }
        errorMessage = nil

        while UIApplication.shared.alternateIconName != requestedIconName {
            let target = requestedIconName
            do {
                // 提交后让 UIKit 做完，即使期间又换了主题。
                try await UIApplication.shared.setAlternateIconName(target)
                // 完成只代表请求被接受，系统报告的名字可能滞后；
                // 只有等待期间又选了新主题才需要再提交一次。
                if target == requestedIconName { return }
            } catch {
                // 新的选择仍应得到一次尝试。
                if target != requestedIconName { continue }
                errorMessage = "桌面图标未能更新，可点击下方重试。"
                return
            }
        }
    }
}

/// 外观设置作用到窗口：固定浅色或深色时覆盖系统外观，弹窗、菜单和 sheet 一起生效；
/// 窗口的 tintColor 换成主题色，系统提示框的按钮也跟着变。
enum WindowAppearance {
    static func apply(_ settings: AppearanceSettings) {
        let style: UIUserInterfaceStyle = switch settings.mode {
        case .system: .unspecified
        case .light: .light
        case .dark: .dark
        }
        let tint = UIColor(settings.theme.color)
        for case let scene as UIWindowScene in UIApplication.shared.connectedScenes {
            for window in scene.windows {
                window.overrideUserInterfaceStyle = style
                window.tintColor = tint
            }
        }
    }
}
