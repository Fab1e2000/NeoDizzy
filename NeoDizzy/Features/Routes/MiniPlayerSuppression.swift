// 移植自 MeloX（GPLv3）App/AppNavigation.swift 的 SetTabViewBottomAccessorySuppressedAction。

import SwiftUI

/// 页面临时收起标签栏上方的迷你播放器，例如多选时给底部操作栏让位；离开页面时要恢复。
struct SetMiniPlayerSuppressedAction {
    private let action: (Bool) -> Void

    init(action: @escaping (Bool) -> Void = { _ in }) {
        self.action = action
    }

    func callAsFunction(_ isSuppressed: Bool) {
        action(isSuppressed)
    }
}

private struct SetMiniPlayerSuppressedActionKey: EnvironmentKey {
    static let defaultValue = SetMiniPlayerSuppressedAction()
}

extension EnvironmentValues {
    var setMiniPlayerSuppressed: SetMiniPlayerSuppressedAction {
        get { self[SetMiniPlayerSuppressedActionKey.self] }
        set { self[SetMiniPlayerSuppressedActionKey.self] = newValue }
    }
}
