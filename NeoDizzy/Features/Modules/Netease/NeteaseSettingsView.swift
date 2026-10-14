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
                    Picker("Wi-Fi 音质", selection: $settings.wifi) {
                        ForEach(NeteaseQuality.allCases) { Text($0.title).tag($0) }
                    }
                    Picker("蜂窝网络音质", selection: $settings.cellular) {
                        ForEach(NeteaseQuality.allCases) { Text($0.title).tag($0) }
                    }
                } header: {
                    Text("播放音质")
                } footer: {
                    Text("高音质是否可用取决于账号权益和歌曲音源，不可用时自动尝试较低音质。更改当前网络的音质后，将保留播放进度重新加载音源。")
                }
                Section("账号") {
                    if let profile = store.profile {
                        LabeledContent("昵称", value: profile.nickname)
                    } else {
                        Button("登录网易云音乐") { showsLogin = true }
                    }
                    Link("网易云音乐官网", destination: URL(string: "https://music.163.com")!)
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

struct NeteaseHeartModeButton: View {
    @Environment(NeteaseStore.self) private var store
    @Environment(PlayerStore.self) private var player
    @Environment(NowPlayingPresentation.self) private var nowPlaying
    @State private var starting = false
    @State private var error: String?
    var body: some View {
        Button {
            if player.isHeartMode { player.disableHeartMode() }
            else { starting = true }
        } label: {
            HStack {
                Label(player.isHeartMode ? "退出心动模式" : "心动模式", systemImage: "heart.circle.fill")
                Spacer()
                if starting { ProgressView() }
            }
            .padding(.vertical, 10)
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .disabled(starting)
        .task(id: starting) {
            guard starting else { return }
            defer { starting = false }
            do {
                let result = try await store.heartModeSongs()
                try Task.checkCancellation()
                player.play(result.songs, startAt: 0, sourceID: result.playlistID, heartMode: true)
                nowPlaying.isPresented = true
            } catch is CancellationError { }
            catch { self.error = error.localizedDescription }
        }
        .alert("无法开启心动模式", isPresented: Binding(get: { error != nil }, set: { if !$0 { error = nil } })) {
            Button("好", role: .cancel) { error = nil }
        } message: { Text(error ?? "") }
    }
}
