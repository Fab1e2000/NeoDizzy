import SwiftUI

struct LocalPlaylistsView: View {
    @Environment(OfflineLibraryStore.self) private var library
    @State private var creating = false
    @State private var name = ""
    @State private var failure: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Button("新建歌单", systemImage: "plus") { name = ""; creating = true }
            if library.localPlaylists.isEmpty {
                ContentUnavailableView("还没有本地歌单", systemImage: "music.note.list", description: Text("新建歌单后，可以从本地专辑的歌曲菜单添加音乐。"))
            }
            ForEach(library.localPlaylists) { playlist in
                NavigationLink { LocalPlaylistDetailView(id: playlist.id) } label: {
                    Label {
                        VStack(alignment: .leading) {
                            Text(playlist.title)
                            Text("\(playlist.tracks.count) 首").font(.caption).foregroundStyle(.secondary)
                        }
                    } icon: { Image(systemName: "music.note.list") }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.vertical, 8)
                }
                .buttonStyle(.plain)
                .contextMenu {
                    Button("删除歌单", systemImage: "trash", role: .destructive) {
                        Task { do { try await library.deletePlaylist(playlist) } catch { failure = error.localizedDescription } }
                    }
                }
            }
            if let failure { Text(failure).font(.caption).foregroundStyle(.red) }
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

    var body: some View {
        Group {
            if let playlist = library.localPlaylists.first(where: { $0.id == id }) {
                List {
                    HStack {
                        Button("播放", systemImage: "play.fill") { play(playlist.tracks, shuffled: false) }
                        Spacer()
                        Button("随机播放", systemImage: "shuffle") { play(playlist.tracks, shuffled: true) }
                    }.disabled(playlist.tracks.isEmpty)
                    ForEach(Array(playlist.tracks.enumerated()), id: \.offset) { index, track in
                        Button { player.play(playlist.tracks, startAt: index) } label: {
                            VStack(alignment: .leading, spacing: 4) {
                                Text(track.title).foregroundStyle(.primary)
                                Text(track.artists).font(.caption).foregroundStyle(.secondary)
                            }
                        }.buttonStyle(.plain)
                    }
                    if let failure { Text(failure).foregroundStyle(.red) }
                }
                .navigationTitle(playlist.title)
                .toolbar { Button("删除歌单", systemImage: "trash", role: .destructive) { confirmingDelete = true } }
                .confirmationDialog("删除歌单？音乐文件会保留。", isPresented: $confirmingDelete, titleVisibility: .visible) {
                    Button("删除歌单", role: .destructive) {
                        Task {
                            do { try await library.deletePlaylist(playlist); dismiss() }
                            catch { failure = error.localizedDescription }
                        }
                    }
                }
            } else { ContentUnavailableView("找不到歌单", systemImage: "music.note.list") }
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
