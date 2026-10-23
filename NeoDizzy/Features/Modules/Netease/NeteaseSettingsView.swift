import SwiftUI

struct NeteaseSettingsView: View {
    let store: NeteaseStore
    @Environment(\.dismiss) private var dismiss
    @State private var showsLogin = false
    var body: some View {
        @Bindable var settings = store.playbackSettings
        NavigationStack {
            Form {
                Section {
                    Picker("音质", selection: $settings.quality) {
                        ForEach(NeteaseQuality.allCases) { Text($0.title).tag($0) }
                    }
                } header: { Text("播放与下载") }
                Section("账号") {
                    if let profile = store.profile {
                        LabeledContent("昵称", value: profile.nickname)
                    } else {
                        Button("登录网易云音乐") { showsLogin = true }
                    }
                    Link("网易云音乐官网", destination: URL(string: "https://music.163.com")!)
                }
                if let error = store.sessionError {
                    Section {
                        Text(error).foregroundStyle(.red)
                        Button("重试清除凭据") { store.logout() }
                    }
                }
                if store.profile != nil {
                    Section { Button("退出登录", role: .destructive) { store.logout() } }
                }
            }
            .navigationTitle("网易云音乐设置")
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button(role: .close) { dismiss() } } }
            .sheet(isPresented: $showsLogin) { NeteaseLoginView(store: store) }
        }
    }
}
