import SwiftUI

/// 资料库「歌单」：本地歌单（可新建、删除）和账号里的在线歌单放在同一个网格里。
struct LocalPlaylistsView: View {
    var online: [LibraryShelfItem] = []
    var showsLocal = true
    var showsOrigin = false
    var showsFavorites = false
    @Environment(FavoritesStore.self) private var favorites
    @Environment(OfflineLibraryStore.self) private var library
    @State private var creating = false
    @State private var name = ""
    @State private var failure: String?
    @State private var deletingPlaylist: LocalPlaylist?

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            if !showsFavorites && (!showsLocal || library.localPlaylists.isEmpty) && online.isEmpty {
                ContentUnavailableView("没有播放列表", systemImage: "music.note.list",
                    description: Text(showsLocal ? "点击右上角新建播放列表，或同步已启用平台的播放列表。" : "这个来源下还没有播放列表。"))
            }
            LazyVGrid(columns: DizzyGrid.columns, alignment: .leading, spacing: 22) {
                if showsFavorites {
                    NavigationLink(value: AppRoute.favorites) {
                        VStack(alignment: .leading, spacing: 6) {
                            RoundedRectangle(cornerRadius: 10)
                                .fill(DizzyPalette.surface)
                                .aspectRatio(1, contentMode: .fit)
                                .overlay {
                                    Image(systemName: "star.fill")
                                        .resizable().scaledToFit().padding(38)
                                        .foregroundStyle(.pink)
                                }
                            Text("喜欢的歌").font(.subheadline.weight(.semibold))
                            Text("\(favorites.songs.count) 首").font(.caption).foregroundStyle(DizzyPalette.mutedText)
                        }
                        .foregroundStyle(DizzyPalette.text)
                        .contentShape(.rect)
                    }
                    .buttonStyle(.plain)
                }
                ForEach(showsLocal ? library.localPlaylists : []) { playlist in
                    AlbumNavigationLink(value: .localPlaylist(id: playlist.id), artworkURL: playlist.coverURL) {
                        VStack(alignment: .leading, spacing: 6) {
                            ArtworkImage(url: playlist.coverURL)
                                .libraryOriginMark(showsOrigin ? .local : nil, tracks: playlist.tracks)
                                .contentShape(.contextMenuPreview, .rect(cornerRadius: 10))
                                .contextMenu {
                                    Button("删除", systemImage: "trash", role: .destructive) { deletingPlaylist = playlist }
                                } preview: {
                                    ArtworkImage(url: playlist.coverURL).frame(width: 260, height: 260)
                                        .environment(\.albumNavigationSource, nil)
                                }
                            VStack(alignment: .leading, spacing: 6) {
                                Text(playlist.title).font(.subheadline.weight(.semibold)).lineLimit(2)
                                Text("本地播放列表").font(.caption).foregroundStyle(DizzyPalette.mutedText)
                                Text("\(playlist.tracks.count) 首").font(.caption).foregroundStyle(DizzyPalette.mutedText)
                            }.multilineTextAlignment(.leading)
                        }
                        .contentShape(.rect)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(playlist.title)
                    .prefetchAlbumArtwork(url: playlist.coverURL)
                }
                ForEach(online) { LibraryShelfCard(item: $0, showsOrigin: showsOrigin) }
            }
            if let failure { Text(failure).font(.caption).foregroundStyle(.red) }
        }
        .toolbar {
            if showsLocal {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("新建播放列表", systemImage: "text.badge.plus") {
                        name = ""
                        creating = true
                    }
                }
            }
        }
        .confirmationDialog("删除播放列表？", item: $deletingPlaylist, titleVisibility: .visible) { playlist in
            Button("删除", role: .destructive) {
                Task { do { try await library.deletePlaylist(playlist) } catch { failure = error.localizedDescription } }
            }
            Button("取消", role: .cancel) { }
        } message: { playlist in
            Text(playlist.source == nil ? "将删除「\(playlist.title)」，音乐文件会保留。" : "将删除「\(playlist.title)」及此歌单目录中的下载文件。")
        }
        .alert("新建播放列表", isPresented: $creating) {
            TextField("播放列表名称", text: $name)
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
                        Text("本地播放列表")
                    } actions: {
                        AlbumPlaybackActions(isEmpty: playlist.tracks.isEmpty) { shuffled in
                            play(playlist.tracks, shuffled: shuffled)
                        }
                    }
                    ForEach(Array(playlist.tracks.enumerated()), id: \.offset) { index, track in
                        SongRow(track: track) { player.play(playlist.tracks, startAt: index) }
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
    @Environment(\.dismiss) private var dismiss
    var body: some View {
        NavigationStack {
            List { LocalPlaylistPickerContent(track: track) }
                .navigationTitle("加入播放列表")
                .toolbar { Button("取消", role: .cancel) { dismiss() } }
        }
        #if os(macOS)
        .frame(minWidth: 420, minHeight: 400)
        #endif
    }
}

/// Local targets remain available regardless of the song's online provider or download state.
struct LocalPlaylistPickerContent: View {
    let track: Track
    @Environment(OfflineLibraryStore.self) private var library
    @Environment(\.dismiss) private var dismiss
    @State private var creating = false
    @State private var name = ""
    @State private var failure: String?
    @State private var saving = false

    var body: some View {
        Section {
            Button("新建播放列表", systemImage: "text.badge.plus") { name = ""; creating = true }
            ForEach(library.localPlaylists) { playlist in
                Button { save(to: playlist) } label: {
                    HStack(spacing: 12) {
                        ArtworkImage(url: playlist.coverURL, cornerRadius: 6).frame(width: 48, height: 48)
                        VStack(alignment: .leading, spacing: 4) {
                            Text(playlist.title).foregroundStyle(.primary)
                            Text("\(playlist.tracks.count) 首").font(.caption).foregroundStyle(.secondary)
                        }
                    }
                }
            }
            if saving { ProgressView("正在保存") }
            if let failure { Text(failure).foregroundStyle(.red) }
        } header: {
            Text("本地")
        } footer: {
            Text("保存在本机；在线歌曲仍通过原来源播放。")
        }
        .disabled(saving)
        .alert("新建播放列表", isPresented: $creating) {
            TextField("播放列表名称", text: $name)
            Button("取消", role: .cancel) { }
            Button("创建并添加") { save(to: nil) }
                .disabled(name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
        }
    }

    private func save(to playlist: LocalPlaylist?) {
        guard !saving else { return }
        saving = true; failure = nil
        Task {
            defer { saving = false }
            do {
                if let playlist { try await library.add(track, to: playlist) }
                else { try await library.savePlaylist(title: name, tracks: [track]) }
                dismiss()
            } catch { failure = error.localizedDescription }
        }
    }
}
