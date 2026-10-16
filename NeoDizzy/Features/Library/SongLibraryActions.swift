import SwiftUI

/// 所有歌曲列表共用的收藏操作；播放器复用同一喜欢按钮和歌单呈现入口。
@Observable @MainActor final class SongActionPresentation {
    var playlist = false
    var login = false
    var failure: String?
}

struct SongLibraryActions: View {
    let track: Track
    let presentation: SongActionPresentation
    var body: some View {
        FavoriteButton(track: track, presentation: presentation)
        Button("加入歌单", systemImage: "text.badge.plus") { presentation.playlist = true }
    }
}

/// 弹窗必须挂在歌曲行或播放器上，不能挂在收起后会销毁的菜单项上。
struct SongActionPresentationModifier: ViewModifier {
    let track: Track
    @Bindable var presentation: SongActionPresentation
    @Environment(NeteaseStore.self) private var netease: NeteaseStore?
    func body(content: Content) -> some View {
        content
            .songPlaylistSheet(isPresented: $presentation.playlist, track: track)
            .sheet(isPresented: $presentation.login) { if let netease { NeteaseLoginView(store: netease) } }
            .alert("喜欢操作失败", item: $presentation.failure) { _ in Button("好", role: .cancel) { } } message: { Text($0) }
    }
}

nonisolated enum SongPlaylistDestination: Equatable {
    case netease(Int), local, unavailable

    static func resolve(_ track: Track, hasLocalFile: Bool) -> Self {
        // 已下载的网易云歌曲仍然写入原平台歌单。
        if track.remoteSource?.providerID == "netease",
           let id = (track.remoteSource?.itemID).flatMap(Int.init) { return .netease(id) }
        return hasLocalFile ? .local : .unavailable
    }
}

extension View {
    func songPlaylistSheet(isPresented: Binding<Bool>, track: Track) -> some View {
        sheet(isPresented: isPresented) { SongPlaylistSheet(track: track) }
    }
}

private struct SongPlaylistSheet: View {
    let track: Track
    @Environment(OfflineLibraryStore.self) private var library
    @Environment(NeteaseStore.self) private var netease: NeteaseStore?
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        switch SongPlaylistDestination.resolve(track, hasLocalFile: library.localFile(for: track) != nil) {
        case .netease(let id):
            if let netease, netease.profile == nil {
                NeteaseLoginView(store: netease)
            } else if netease != nil {
                NeteasePlaylistPicker(songID: id)
            } else {
                unavailable("网易云模块当前不可用。")
            }
        case .local:
            LocalPlaylistPicker(track: track)
        case .unavailable:
            unavailable("这首歌尚无可用的平台歌单接口。下载歌曲后，可以加入本地歌单。")
        }
    }

    private func unavailable(_ message: String) -> some View {
        NavigationStack {
            ContentUnavailableView("暂时无法加入歌单", systemImage: "music.note.list", description: Text(message))
                .navigationTitle("加入歌单")
                .toolbar { ToolbarItem(placement: .cancellationAction) { Button("关闭") { dismiss() } } }
        }
    }
}
