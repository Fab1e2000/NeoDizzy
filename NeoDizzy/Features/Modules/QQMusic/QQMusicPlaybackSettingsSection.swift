import SwiftUI

struct QQMusicPlaybackSettingsSection: View {
    @Bindable var settings: QQMusicPlaybackSettings
    var body: some View {
        Section {
            Picker("音质", selection: $settings.quality) {
                ForEach(QQMusicQuality.allCases) { quality in Text(quality.title).tag(quality) }
            }
        } header: {
            Text("播放与下载")
        } footer: {
            Text("播放和下载使用同一音质。歌曲或账号不支持所选音质时，自动尝试较低音质。")
        }
    }
}
