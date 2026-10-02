import SwiftUI

// 参照 NeoBili 的 LeftEdgeTapDeadZone：仅拦截页面左侧点击，返回仍交给原生导航手势。
enum AlbumInteractionSettings {
    static let key = "album.leftEdgeDeadZoneWidth"
    static let defaultWidth = 30.0
}

extension View {
    func albumLeftEdgeDeadZone() -> some View { modifier(AlbumLeftEdgeDeadZone()) }
}

private struct AlbumLeftEdgeDeadZone: ViewModifier {
    @AppStorage(AlbumInteractionSettings.key) private var width = AlbumInteractionSettings.defaultWidth

    func body(content: Content) -> some View {
        content.overlay(alignment: .leading) {
            if width.isFinite && width >= 1 {
                Color.clear.frame(width: min(width, 100))
                    .contentShape(.rect)
                    .onTapGesture {}
                    .accessibilityHidden(true)
            }
        }
    }
}

struct AlbumInteractionSettingsView: View {
    @AppStorage(AlbumInteractionSettings.key) private var width = AlbumInteractionSettings.defaultWidth

    var body: some View {
        Form {
            Section {
                LabeledContent("左侧防误触区域", value: "\(Int(width.isFinite ? min(max(width, 0), 100) : 30)) pt")
                Slider(value: $width, in: 0...100, step: 1)
                    .accessibilityLabel("左侧防误触区域宽度")
                Button("恢复默认") { width = AlbumInteractionSettings.defaultWidth }
            } footer: {
                Text("专辑页面左侧此宽度内的点击不触发曲目或按钮，方便从边缘返回。设为 0 可关闭；从该区域开始的列表滚动也会被拦截。")
            }
        }
        .navigationTitle("专辑页面")
        .overlay(alignment: .leading) {
            Color.accentColor.opacity(0.12)
                .frame(width: width.isFinite ? min(max(width, 0), 100) : 30)
                .allowsHitTesting(false)
                .accessibilityHidden(true)
        }
    }
}
