import SwiftUI

struct QQMusicPlaylistPicker: View {
    let songMid: String
    @Environment(QQMusicStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    @State private var showsLogin = false
    @State private var loading = true
    @State private var adding: String?
    @State private var error: String?

    var body: some View {
        Section("QQ 音乐") {
            if store.credential == nil {
                Button("登录 QQ 音乐") { showsLogin = true }
            } else {
                if let error { Text(error).foregroundStyle(.secondary) }
                if loading && store.library.writablePlaylists.isEmpty { ProgressView("正在加载歌单") }
                else if !loading && error == nil && store.library.writablePlaylists.isEmpty {
                    ContentUnavailableView("暂无可添加的歌单", systemImage: "music.note.list", description: Text("请先在 QQ 音乐中创建歌单。"))
                }
                ForEach(store.library.writablePlaylists) { playlist in
                    Button {
                        adding = playlist.id; error = nil
                        let revision = store.revision
                        Task {
                            defer { if store.revision == revision { adding = nil } }
                            do {
                                try await store.library.addSong(mid: songMid, to: playlist)
                                guard store.revision == revision else { return }
                                dismiss()
                            } catch is CancellationError { }
                            catch { if store.revision == revision { self.error = error.localizedDescription } }
                        }
                    } label: {
                        HStack(spacing: 12) {
                            ArtworkImage(url: playlist.coverURL, cornerRadius: 6).frame(width: 48, height: 48)
                            Text(playlist.title).foregroundStyle(.primary)
                            Spacer()
                            if adding == playlist.id { ProgressView() }
                        }
                    }
                    .disabled(adding != nil)
                }
                if !loading && error != nil { Button("重新加载") { Task { await load() } } }
            }
        }
        .sheet(isPresented: $showsLogin) { QQMusicLoginView(store: store) }
        .task(id: store.revision) { adding = nil; await load() }
    }

    private func load() async {
        let revision = store.revision
        guard store.credential != nil else { loading = false; return }
        loading = true; error = nil
        defer { if store.revision == revision { loading = false } }
        do { try await store.library.loadPlaylists() }
        catch is CancellationError { }
        catch { if !Task.isCancelled && store.revision == revision { self.error = error.localizedDescription } }
    }
}

struct QQMusicCollectionFavorite: View {
    let collection: QQMusicCollection
    let kind: QQMusicLibraryKind
    @Environment(QQMusicStore.self) private var store
    @State private var error: String?
    @State private var working = false
    @State private var confirmsRemoval = false
    private var owned: Bool { kind == .playlist && store.library.isOwnedPlaylist(collection.id) }
    private var selected: Bool? { store.library.isSubscribed(collection.id, kind: kind) }
    private var requestID: String { "\(store.revision)/\(kind.rawValue)/\(collection.id)" }

    var body: some View {
        Button {
            guard store.credential != nil else { store.showsAccount = true; return }
            if selected == true { confirmsRemoval = true } else { toggle() }
        } label: {
            CollectionLibraryActionLabel(isAdded: owned || selected == true, isWorking: working)
        }
        .disabled(working || owned || (store.credential != nil && selected == nil))
        .accessibilityLabel(owned ? "我的歌单" : selected == true ? "从资料库移除" : "加入资料库")
        .accessibilityHint(selected == true && !owned ? "同时在 QQ 音乐取消收藏" : "同时收藏到 QQ 音乐账号")
        .confirmationDialog("从资料库移除「\(collection.title)」？", isPresented: $confirmsRemoval, titleVisibility: .visible) {
            Button("从资料库移除", role: .destructive) { toggle() }
            Button("取消", role: .cancel) { }
        } message: { Text("QQ 音乐账号也会取消收藏此内容。") }
        .task(id: requestID) { error = nil; working = false; confirmsRemoval = false; await load() }
        .alert("操作失败", isPresented: Binding(get: { error != nil }, set: { if !$0 { error = nil } })) {
            if selected == nil { Button("重试读取收藏状态") { Task { await load() } } }
            Button("好", role: .cancel) { error = nil }
        } message: { Text(error ?? "") }
    }

    private func load() async {
        guard store.credential != nil else { return }
        let id = requestID
        do {
            switch kind {
            case .playlist: try await store.library.loadPlaylists()
            case .album: try await store.library.loadAlbums()
            }
        } catch is CancellationError { }
        catch { if !Task.isCancelled && requestID == id { self.error = error.localizedDescription } }
    }
    private func toggle() {
        let id = requestID
        working = true; error = nil
        Task {
            defer { if requestID == id { working = false } }
            do {
                switch kind {
                case .playlist: try await store.library.togglePlaylist(collection)
                case .album: try await store.library.toggleAlbum(collection)
                }
            } catch is CancellationError { }
            catch { if requestID == id { self.error = error.localizedDescription } }
        }
    }
}
