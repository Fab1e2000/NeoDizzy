import UIKit

/// App 主体与弹层固定浅色；全屏播放器在自己的内容范围内使用深色。
enum WindowAppearance {
    static func apply() {
        for case let scene as UIWindowScene in UIApplication.shared.connectedScenes {
            for window in scene.windows {
                window.overrideUserInterfaceStyle = .light
            }
        }
    }
}
