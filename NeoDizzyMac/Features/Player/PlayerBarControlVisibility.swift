import CoreGraphics

/// 几何观察只保留控件真正依赖的两档阈值，而不是动画中的每一个宽度值。
/// 三栏的位置和连续伸缩仍由 PlayerBarLayout 使用实际 bounds 直接计算。
nonisolated struct PlayerBarControlVisibility: Equatable, Sendable {
    let showsModes: Bool
    let showsVolumeSlider: Bool

    init(width: CGFloat) {
        showsModes = width >= 900
        showsVolumeSlider = width >= 720
    }
}
