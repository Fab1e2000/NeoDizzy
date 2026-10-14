import SwiftUI
import UIKit

struct NeteaseLikeButton: View {
    let songID: Int
    var requestLogin: (() -> Void)? = nil
    @Environment(NeteaseStore.self) private var store
    @State private var error: String?
    @State private var working = false
    private var liked: Bool { store.library.likedIDs.contains(songID) }
    var body: some View {
        Button {
            guard store.profile != nil else { if let requestLogin { requestLogin() } else { store.showsLogin = true }; return }
            working = true
            Task {
                defer { working = false }
                do { try await store.library.toggleLike(songID) }
                catch is CancellationError { }
                catch { self.error = error.localizedDescription }
            }
        } label: {
            Image(systemName: liked ? "heart.fill" : "heart")
                .font(.title3.weight(.semibold))
                .foregroundStyle(liked ? DizzyPalette.accentOnDark : .white)
                .frame(width: 44, height: 44)
                .background(.white.opacity(0.15), in: .circle)
        }
        .buttonStyle(.plain)
        .disabled(working || store.library.pending.contains("song/\(songID)"))
        .accessibilityLabel(liked ? "取消喜欢" : "喜欢这首歌")
        .accessibilityValue(working ? "正在同步" : liked ? "已喜欢" : "未喜欢")
        .task(id: store.revision) {
            if store.profile != nil { try? await store.library.loadLikes() }
        }
        .alert("操作失败", isPresented: Binding(get: { error != nil }, set: { if !$0 { error = nil } })) {
            Button("好", role: .cancel) { error = nil }
        } message: { Text(error ?? "") }
    }
}

struct NeteasePlayerActions: View {
    @Environment(PlayerStore.self) private var player
    let track: Track
    var onImportLyrics: (() -> Void)?
    @Environment(NeteaseStore.self) private var store
    @Environment(\.openRoute) private var openRoute
    @Environment(\.openURL) private var openURL
    @State private var showsPicker = false
    @State private var showsLogin = false
    var body: some View {
        HStack(spacing: 10) {
            if let id = (track.remoteSource?.itemID).flatMap(Int.init) {
                NeteaseLikeButton(songID: id, requestLogin: { showsLogin = true })
                NowPlayingMenuButton {
                    var items: [UIMenuElement] = [
                        UIAction(title: "加入歌单", image: UIImage(systemName: "text.badge.plus")) { _ in
                            if store.profile == nil { showsLogin = true } else { showsPicker = true }
                        },
                        UIAction(title: "相似歌曲", image: UIImage(systemName: "music.note.list")) { _ in openRoute(.netease(.similar(id))) }
                    ]
                    if player.isHeartMode {
                        items.insert(UIAction(title: "退出心动模式", image: UIImage(systemName: "heart.slash")) { _ in
                            player.disableHeartMode()
                        }, at: 0)
                    }
                    if let albumID = Int(track.discID), albumID > 0 {
                        items.append(UIAction(title: "前往专辑", image: UIImage(systemName: "square.stack")) { _ in openRoute(.netease(.album(albumID))) })
                    }
                    items.append(UIAction(title: "在网易云网页中打开", image: UIImage(systemName: "safari")) { _ in
                        openURL(URL(string: "https://music.163.com/#/song?id=\(id)")!)
                    })
                    if let onImportLyrics { items.append(UIAction(title: "导入本地歌词", image: UIImage(systemName: "square.and.arrow.down")) { _ in onImportLyrics() }) }
                    return items
                }.frame(width: 44, height: 44)
            }
        }
        .sheet(isPresented: $showsPicker) {
            if let id = (track.remoteSource?.itemID).flatMap(Int.init) { NeteasePlaylistPicker(songID: id) }
        }
        // A login requested from the full-screen player belongs to that presentation.
        .sheet(isPresented: $showsLogin) {
            NeteaseLoginView(store: store)
        }
    }
}

struct NeteasePlaylistPicker: View {
    let songID: Int
    @Environment(NeteaseStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    @State private var loading = true
    @State private var adding: Int?
    @State private var error: String?
    var body: some View {
        NavigationStack {
            List {
                if let error { Text(error).foregroundStyle(.secondary) }
                if loading && store.library.writablePlaylists.isEmpty {
                    ForEach(0..<5) { _ in
                        HStack(spacing: 12) {
                            RoundedRectangle(cornerRadius: 6).fill(.gray.opacity(0.18))
                                .frame(width: 48, height: 48)
                            Text("我的歌单名称").redacted(reason: .placeholder)
                            Spacer()
                        }
                        .accessibilityHidden(true)
                        .allowsHitTesting(false)
                    }
                }
                else if !loading && error == nil && store.library.writablePlaylists.isEmpty {
                    ContentUnavailableView("暂无可添加的歌单", systemImage: "music.note.list", description: Text("请先在网易云音乐中创建歌单。"))
                }
                ForEach(store.library.writablePlaylists) { playlist in
                    Button {
                        adding = playlist.id; error = nil
                        Task {
                            defer { adding = nil }
                            do { try await store.library.addSong(songID, to: playlist); dismiss() }
                            catch is CancellationError { }
                            catch { self.error = error.localizedDescription }
                        }
                    } label: {
                        HStack(spacing: 12) {
                            ArtworkImage(url: playlist.artworkURL, cornerRadius: 6).frame(width: 48, height: 48)
                            Text(playlist.name).foregroundStyle(.primary)
                            Spacer()
                            if adding == playlist.id { ProgressView() }
                        }
                    }.disabled(adding != nil)
                }
                if !loading && error != nil { Button("重新加载") { Task { await load() } } }
            }
            .navigationTitle("加入歌单")
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("取消", role: .cancel) { dismiss() } } }
            .task(id: store.revision) { await load() }
        }
    }
    private func load() async {
        loading = true; error = nil
        defer { loading = false }
        do { try await store.library.loadPlaylists() }
        catch is CancellationError { }
        catch { self.error = error.localizedDescription }
    }
}

struct NeteaseCollectionFavorite: View {
    let playlist: NeteasePlaylist?
    let album: NeteaseAlbum?
    @Environment(NeteaseStore.self) private var store
    @State private var error: String?
    @State private var working = false
    private var owned: Bool { playlist?.creator?.userId == store.profile?.userId && store.profile != nil }
    private var subscription: Bool? {
        if let playlist { return store.library.isSubscribed(playlist) }
        if let album { return store.library.albumStates[album.id] }
        return nil
    }
    private var selected: Bool { subscription == true }
    private var isReady: Bool {
        (playlist != nil || album != nil) && (store.profile == nil || subscription != nil)
    }
    private var statusRequestID: String {
        "\(store.revision)/\(playlist?.id ?? 0)/\(album?.id ?? 0)"
    }
    var body: some View {
        Button {
            guard store.profile != nil else { store.showsLogin = true; return }
            working = true; error = nil
            Task {
                defer { working = false }
                do {
                    if let playlist { try await store.library.togglePlaylist(playlist) }
                    if let album { try await store.library.toggleAlbum(album) }
                } catch is CancellationError { }
                catch { self.error = error.localizedDescription }
            }
        } label: {
            ZStack {
                Image(systemName: owned || selected ? "checkmark" : "plus")
                    .opacity(working ? 0 : 1)
                if working { ProgressView() }
            }
            .font(.title2.weight(.semibold))
            .frame(width: 30, height: 30)
        }
        .disabled(working || owned || !isReady)
        .accessibilityLabel(owned ? "我的歌单" : selected ? "取消收藏" : "收藏")
        .accessibilityHint(selected && !owned ? "点击取消收藏" : "收藏到网易云音乐账号")
        .task(id: statusRequestID) { await loadSubscription() }
        .alert("收藏失败", isPresented: Binding(get: { error != nil }, set: { if !$0 { error = nil } })) {
            if subscription == nil && (playlist != nil || album != nil) {
                Button("重试读取收藏状态") { Task { await loadSubscription() } }
            }
            Button("好", role: .cancel) { error = nil }
        } message: { Text(error ?? "") }
    }

    private func loadSubscription() async {
        guard store.profile != nil else { return }
        do {
            if let album { try await store.library.loadAlbumStatus(album.id) }
            if let playlist, store.library.isSubscribed(playlist) == nil { try await store.library.loadPlaylists() }
        } catch is CancellationError { }
        catch { if !Task.isCancelled { self.error = error.localizedDescription } }
    }

}
