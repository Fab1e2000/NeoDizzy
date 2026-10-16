import SwiftUI

/// 资料库「歌单」：本地歌单（可新建、删除）和账号里的在线歌单放在同一个网格里。
struct LocalPlaylistsView: View {
    var online: [LibraryShelfItem] = []
    var showsLocal = true
    var showsOrigin = false
    @Environment(OfflineLibraryStore.self) private var library
    @Environment(\.openRoute) private var openRoute
    @State private var creating = false
    @State private var name = ""
    @State private var failure: String?
    @State private var deletingPlaylist: LocalPlaylist?

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            if showsLocal {
                Button { name = ""; creating = true } label: {
                    Label("新建歌单", systemImage: "plus")
                        .font(.subheadline.weight(.semibold))
                        .frame(maxWidth: .infinity, minHeight: 44)
                }
                .buttonStyle(.bordered)
                .buttonBorderShape(.roundedRectangle(radius: 12))
            }
            if (!showsLocal || library.localPlaylists.isEmpty) && online.isEmpty {
                ContentUnavailableView("没有歌单", systemImage: "music.note.list",
                    description: Text(showsLocal ? "新建一个本地歌单，或登录网易云同步账号里的歌单。" : "这个来源下还没有歌单。"))
            }
            LazyVGrid(columns: DizzyGrid.columns, alignment: .leading, spacing: 22) {
                ForEach(showsLocal ? library.localPlaylists : []) { playlist in
                    VStack(alignment: .leading, spacing: 6) {
                        Button { openRoute(.localPlaylist(id: playlist.id)) } label: {
                            ArtworkImage(url: playlist.coverURL)
                                .libraryOriginMark(showsOrigin ? .local : nil)
                        }
                        .buttonStyle(.plain)
                        .contentShape(.contextMenuPreview, .rect(cornerRadius: 10))
                        .accessibilityLabel(playlist.title)
                        .contextMenu {
                            Button("删除", systemImage: "trash", role: .destructive) { deletingPlaylist = playlist }
                        } preview: {
                            ArtworkImage(url: playlist.coverURL).frame(width: 260, height: 260)
                        }
                        Button { openRoute(.localPlaylist(id: playlist.id)) } label: {
                            VStack(alignment: .leading, spacing: 6) {
                                Text(playlist.title).font(.subheadline.weight(.semibold)).lineLimit(2)
                                Text("本地歌单").font(.caption).foregroundStyle(DizzyPalette.mutedText)
                                Text("\(playlist.tracks.count) 首").font(.caption).foregroundStyle(DizzyPalette.mutedText)
                            }.multilineTextAlignment(.leading)
                        }.buttonStyle(.plain)
                    }
                    .prefetchAlbumArtwork(url: playlist.coverURL)
                }
                ForEach(online) { LibraryShelfCard(item: $0, showsOrigin: showsOrigin) }
            }
            if let failure { Text(failure).font(.caption).foregroundStyle(.red) }
        }
        .confirmationDialog("删除歌单？", item: $deletingPlaylist, titleVisibility: .visible) { playlist in
            Button("删除", role: .destructive) {
                Task { do { try await library.deletePlaylist(playlist) } catch { failure = error.localizedDescription } }
            }
            Button("取消", role: .cancel) { }
        } message: { playlist in
            Text(playlist.source == nil ? "将删除「\(playlist.title)」，音乐文件会保留。" : "将删除「\(playlist.title)」及此歌单目录中的下载文件。")
        }
        .alert("新建歌单", isPresented: $creating) {
            TextField("歌单名称", text: $name)
            Button("取消", role: .cancel) { }
            Button("创建") {
                Task { do { try await library.savePlaylist(title: name, tracks: []) } catch { failure = error.localizedDescription } }
            }.disabled(name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
        }
    }
}

struct LocalPlaylistDetailView: View {
    let id: String
    @Environment(OfflineLibraryStore.self) private var library
    @Environment(PlayerStore.self) private var player
    @Environment(\.dismiss) private var dismiss
    @State private var failure: String?
    @State private var confirmingDelete = false

    private var playlist: LocalPlaylist? { library.localPlaylists.first { $0.id == id } }

    var body: some View {
        AlbumDetailScrollView(artworkURL: playlist?.coverURL) {
            if let playlist {
                LazyVStack(alignment: .leading, spacing: 0) {
                    AlbumHero(artworkURL: playlist.coverURL, title: playlist.title,
                              metadata: "\(playlist.tracks.count) 首") {
                        Text("本地歌单")
                    } actions: {
                        AlbumPlaybackActions(isEmpty: playlist.tracks.isEmpty) { shuffled in
                            play(playlist.tracks, shuffled: shuffled)
                        }
                    }
                    ForEach(Array(playlist.tracks.enumerated()), id: \.offset) { index, track in
                        AlbumTrackRow(track: track, displayNumber: String(index + 1)) { player.play(playlist.tracks, startAt: index) }
                            .padding(.horizontal, -20)
                    }
                    if playlist.tracks.isEmpty {
                        ContentUnavailableView("歌单还是空的", systemImage: "music.note.list",
                            description: Text("从歌曲菜单选择「加入歌单」来添加音乐。"))
                    }
                    if let failure { Text(failure).foregroundStyle(.red).padding(.vertical) }
                }
                .padding(.horizontal, 20).padding(.bottom, 32)
            } else { ContentUnavailableView("找不到歌单", systemImage: "music.note.list") }
        }
        .dizzyPageBackground()
        #if os(iOS)
        .safeAreaPadding(.top, 5)
        .navigationTitle("")
        .toolbar(.visible, for: .navigationBar)
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(.hidden, for: .navigationBar)
        #endif
        .toolbar {
            if playlist != nil {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("删除歌单", systemImage: "trash", role: .destructive) { confirmingDelete = true }
                }
            }
        }
        .confirmationDialog(playlist?.source == nil ? "删除歌单？音乐文件会保留。" : "删除歌单及其下载文件？", isPresented: $confirmingDelete, titleVisibility: .visible) {
            if let playlist {
                Button("删除歌单", role: .destructive) {
                    Task {
                        do { try await library.deletePlaylist(playlist); dismiss() }
                        catch { failure = error.localizedDescription }
                    }
                }
            }
        }
    }

    private func play(_ tracks: [Track], shuffled: Bool) {
        guard !tracks.isEmpty else { return }
        player.play(tracks, startAt: shuffled ? Int.random(in: tracks.indices) : 0)
        if player.isShuffled != shuffled { player.toggleShuffle() }
    }
}

struct LocalPlaylistPicker: View {
    let track: Track
    @Environment(OfflineLibraryStore.self) private var library
    @Environment(\.dismiss) private var dismiss
    @State private var name = ""
    @State private var failure: String?

    var body: some View {
        NavigationStack {
            List {
                Section("新建歌单") {
                    TextField("歌单名称", text: $name)
                    Button("创建并添加") {
                        Task {
                            do { try await library.savePlaylist(title: name, tracks: [track]); dismiss() }
                            catch { failure = error.localizedDescription }
                        }
                    }.disabled(name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
                Section("已有歌单") {
                    ForEach(library.localPlaylists) { playlist in
                        Button(playlist.title) {
                            Task {
                                do { try await library.add(track, to: playlist); dismiss() }
                                catch { failure = error.localizedDescription }
                            }
                        }
                    }
                }
                if let failure { Text(failure).foregroundStyle(.red) }
            }
            .navigationTitle("加入歌单")
            .toolbar { Button("完成") { dismiss() } }
        }
        #if os(macOS)
        .frame(minWidth: 420, minHeight: 400)
        #endif
    }
}
