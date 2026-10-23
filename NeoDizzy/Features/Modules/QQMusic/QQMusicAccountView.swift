import SwiftUI

struct QQMusicAccountView: View {
    let store: QQMusicStore
    @Environment(\.dismiss) private var dismiss
    @State private var signingOut = false

    var body: some View {
        Group {
        if store.credential == nil {
            QQMusicLoginView(store: store)
        } else {
            NavigationStack {
                Form {
                    Section {
                        HStack(spacing: 12) {
                            AvatarImage(url: store.credential?.avatarURL, size: 44)
                            LabeledContent("账号", value: store.accountTitle)
                        }
                        Button("退出登录", role: .destructive) {
                            signingOut = true
                            Task {
                                await store.signOut()
                                signingOut = false
                                if store.sessionError == nil { dismiss() }
                            }
                        }.disabled(signingOut)
                    }
                    QQMusicPlaybackSettingsSection(settings: store.playbackSettings)
                }
                .task(id: store.revision) { await store.refreshProfile() }
                .navigationTitle("QQ 音乐")
                .toolbar { ToolbarItem(placement: .confirmationAction) { Button("完成") { dismiss() } } }
            }
        }
        }.alert("凭据保存失败", isPresented: Binding(get: { store.sessionError != nil }, set: { if !$0 { store.sessionError = nil } })) {
            Button("重试清除") { Task { await store.signOut() } }
            Button("关闭", role: .cancel) { store.sessionError = nil }
        } message: { Text(store.sessionError ?? "") }
    }
}
