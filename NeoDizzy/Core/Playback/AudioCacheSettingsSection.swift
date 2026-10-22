import SwiftUI

struct AudioCacheSettingsSection: View {
    private var cache: AudioPlaybackCache { .shared }
    @State private var confirmsClear = false
    var body: some View {
        Section {
            LabeledContent("音频缓存", value: ByteCountFormatter.string(fromByteCount: cache.bytes, countStyle: .file))
            Button("清理音频缓存", role: .destructive) { confirmsClear = true }
            if let issue = cache.issue { Text(issue).foregroundStyle(.secondary) }
        } header: { Text("听歌缓存") }
        .confirmationDialog("清理听歌缓存？", isPresented: $confirmsClear, titleVisibility: .visible) {
            Button("清理缓存", role: .destructive) { cache.clear() }
            Button("取消", role: .cancel) { }
        }
    }
}
