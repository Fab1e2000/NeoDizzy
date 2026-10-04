import SwiftUI

// MeloX LyricsAppearanceSettingsView: focus-position slider, 5–80%, 1% steps.
// NeoDizzy defaults to the player's center rather than MeloX's upper focus point.
struct LyricsSettingsView: View {
    @AppStorage("lyrics.focusPosition") private var focusPosition = 0.5

    var body: some View {
        Form {
            Section {
                LabeledContent("高亮行纵向位置", value: "距顶部 \(Int(focusPosition * 100))%")
                Slider(value: $focusPosition, in: 0.05...0.8, step: 0.01)
                    .accessibilityLabel("高亮行纵向位置")
                    .accessibilityValue("距顶部 \(Int(focusPosition * 100))%")
                Button("恢复居中") { focusPosition = 0.5 }
            } footer: {
                Text("默认在播放器中部高亮当前歌词。位置会避开歌曲信息和底部播放控制；设置立即生效。")
            }
        }
        .safeAreaPadding(.top, 5)
        .navigationTitle("歌词")
        .navigationBarTitleDisplayMode(.inline)
    }
}
