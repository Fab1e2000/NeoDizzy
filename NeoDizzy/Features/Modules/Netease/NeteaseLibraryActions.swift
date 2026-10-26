import SwiftUI
import UIKit

struct NeteasePlayerActions: View {
    @Environment(PlayerStore.self) private var player
    let track: Track
    var onImportLyrics: (() -> Void)?
    @Environment(NeteaseStore.self) private var store
    @Environment(NeteaseContentCache.self) private var contentCache
    @Environment(DownloadStore.self) private var downloads
    @Environment(OfflineLibraryStore.self) private var library
    @Environment(\.openRoute) private var openRoute
    @State private var showsPicker = false
    @State private var albumNavigation = AlbumNavigationPreparation()
    var body: some View {
        HStack(spacing: 4.25) {
            if (track.remoteSource?.itemID).flatMap(Int.init) != nil {
                FavoriteButton(track: track, playerStyle: true)
                NowPlayingMenuButton(track: track) {
                    var items: [UIMenuElement] = [
                        UIAction(title: "加入歌单", image: UIImage(systemName: "text.badge.plus")) { _ in
                            showsPicker = true
                        }
                    ]
                    if let albumID = Int(track.discID), albumID > 0 {
                        items.append(UIAction(title: "前往专辑", image: UIImage(systemName: "square.stack")) { _ in
                            let page = contentCache.page(.route(.album(albumID)), revision: store.revision)
                            if page.title.isEmpty { page.title = track.albumTitle }
                            if page.artwork == nil { page.artwork = track.coverURL }
                            if let route = albumNavigation.begin(.netease(.album(albumID)), artworkURL: page.artwork) { openRoute(route) }
                        })
                    }
                    // 听完缓存好的歌可以直接存成下载，不再联网。
                    if library.localFile(for: track) == nil, player.cachedQuality(for: track) != nil {
                        let quality = store.playbackSettings.quality
                        items.append(UIAction(title: "转为下载", image: UIImage(systemName: "arrow.down.circle")) { [downloads, track] _ in
                            Task { await downloads.enqueueNeteaseSong(track, quality: quality) }
                        })
                    }
                    if let onImportLyrics { items.append(UIAction(title: "导入本地歌词", image: UIImage(systemName: "square.and.arrow.down")) { _ in onImportLyrics() }) }
                    return items
                }.frame(width: 44, height: 44)
            }
        }
        .songPlaylistSheet(isPresented: $showsPicker, track: track)
        .preparedAlbumNavigation(albumNavigation)
        .onChange(of: track.id) { albumNavigation.cancel() }
        .onChange(of: store.revision) { albumNavigation.cancel() }
    }
}

struct NeteasePlaylistPicker: View {
    let songID: Int
    @Environment(NeteaseStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    @State private var showsLogin = false
    @State private var loading = true
    @State private var adding: Int?
    @State private var error: String?
    var body: some View {
        Section("网易云音乐") {
            if store.profile == nil {
                Button("登录网易云音乐") { showsLogin = true }
            } else {
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
                        let revision = store.revision
                        Task {
                            defer { if store.revision == revision { adding = nil } }
                            do {
                                try await store.library.addSong(songID, to: playlist)
                                guard store.revision == revision else { return }
                                dismiss()
                            } catch is CancellationError { }
                            catch { if store.revision == revision { self.error = error.localizedDescription } }
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
        }
        .sheet(isPresented: $showsLogin) { NeteaseLoginView(store: store) }
        .task(id: store.revision) { adding = nil; await load() }
    }

    private func load() async {
        guard store.profile != nil else { loading = false; return }
        let revision = store.revision
        loading = true; error = nil
        defer { if store.revision == revision { loading = false } }
        do { try await store.library.loadPlaylists() }
        catch is CancellationError { }
        catch { if !Task.isCancelled && store.revision == revision { self.error = error.localizedDescription } }
    }
}

struct NeteaseCollectionFavorite: View {
    let playlist: NeteasePlaylist?
    let album: NeteaseAlbum?
    @Environment(NeteaseStore.self) private var store
    @State private var error: String?
    @State private var working = false
    @State private var confirmsRemoval = false
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
        // 网易云的收藏就是资料库：收藏 = 加入资料库，取消前先确认。
        Button {
            guard store.profile != nil else { store.showsLogin = true; return }
            if selected { confirmsRemoval = true } else { toggle() }
        } label: {
            CollectionLibraryActionLabel(isAdded: owned || selected, isWorking: working)
        }
        .disabled(working || owned || !isReady)
        .accessibilityLabel(owned ? "我的歌单" : selected ? "从资料库移除" : "加入资料库")
        .accessibilityHint(selected && !owned ? "同时在网易云取消收藏" : "同时收藏到网易云音乐账号")
        .confirmationDialog("从资料库移除「\(playlist?.name ?? album?.name ?? "")」？", isPresented: $confirmsRemoval, titleVisibility: .visible) {
            Button("从资料库移除", role: .destructive) { toggle() }
            Button("取消", role: .cancel) { }
        } message: {
            Text(playlist != nil ? "网易云账号也会取消收藏这个歌单。" : "网易云账号也会取消收藏这张专辑。")
        }
        .task(id: statusRequestID) { await loadSubscription() }
        .alert("操作失败", isPresented: Binding(get: { error != nil }, set: { if !$0 { error = nil } })) {
            if subscription == nil && (playlist != nil || album != nil) {
                Button("重试读取收藏状态") { Task { await loadSubscription() } }
            }
            Button("好", role: .cancel) { error = nil }
        } message: { Text(error ?? "") }
    }

    private func toggle() {
        working = true; error = nil
        Task {
            defer { working = false }
            do {
                if let playlist { try await store.library.togglePlaylist(playlist) }
                if let album { try await store.library.toggleAlbum(album) }
            } catch is CancellationError { }
            catch { self.error = error.localizedDescription }
        }
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

/// 网易云专辑页的第三个按钮：先是「加入资料库」，加入之后同一个位置变成「下载」。
/// 取消收藏改为长按下载按钮。
struct NeteaseAlbumLibraryAction: View {
    let album: NeteaseAlbum?
    let id: Int
    let title: String
    let coverURL: URL?
    let isLoaded: Bool
    @Environment(NeteaseStore.self) private var store

    var body: some View {
        #if os(iOS)
        if store.library.albumStates[id] == true {
            NeteaseDownloadButton(kind: "album", id: id, title: title, coverURL: coverURL)
                .disabled(!isLoaded)
                .contextMenu {
                    if let album {
                        Button("从资料库移除", systemImage: "minus.circle", role: .destructive) {
                            Task { try? await store.library.toggleAlbum(album) }
                        }
                    }
                }
        } else {
            NeteaseCollectionFavorite(playlist: nil, album: album)
        }
        #else
        NeteaseCollectionFavorite(playlist: nil, album: album)
        #endif
    }
}
