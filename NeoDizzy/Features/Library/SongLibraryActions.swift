import SwiftUI

/// 所有歌曲列表共用的收藏操作；播放器复用同一喜欢按钮和歌单呈现入口。
@Observable @MainActor final class SongActionPresentation {
    var playlist = false
    var login = false
    var failure: String?

    func toggleFavorite(_ track: Track, favorites: FavoritesStore, modules: ModuleRegistry) {
        if let provider = track.remoteSource?.providerID, modules.requiresLogin(providerID: provider) {
            login = true
            return
        }
        let target = !favorites.contains(track)
        Task {
            do { try await favorites.setLiked(track, target) }
            catch is CancellationError { }
            catch { failure = error.localizedDescription }
        }
    }
}

/// 弹窗必须挂在歌曲行或播放器上，不能挂在收起后会销毁的菜单项上。
struct SongActionPresentationModifier: ViewModifier {
    let track: Track
    @Bindable var presentation: SongActionPresentation
    @Environment(ModuleRegistry.self) private var modules
    func body(content: Content) -> some View {
        content
            .songPlaylistSheet(isPresented: $presentation.playlist, track: track)
            .sheet(isPresented: $presentation.login) {
                if let provider = track.remoteSource?.providerID { modules.loginView(providerID: provider) }
            }
            .alert("喜欢操作失败", item: $presentation.failure) { _ in Button("好", role: .cancel) { } } message: { Text($0) }
    }
}

extension View {
    func songPlaylistSheet(isPresented: Binding<Bool>, track: Track) -> some View {
        sheet(isPresented: isPresented) { SongPlaylistSheet(track: track) }
    }
}

struct SongPlaylistSheet: View {
    let track: Track
    @Environment(ModuleRegistry.self) private var modules
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                LocalPlaylistPickerContent(track: track)
                if let picker = modules.playlistPicker(for: track) { picker }
            }
            .navigationTitle("加入播放列表")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消", role: .cancel) { dismiss() }
                }
            }
        }
    }
}
