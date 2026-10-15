import SwiftUI

struct LocalLibraryView: View {
    @Environment(OfflineLibraryStore.self) private var library
    @Environment(DownloadStore.self) private var downloads
    @State private var showsDownloads = false
    @State private var query = ""
    @State private var preview: [LocalLibraryAlbumItem] = []
    private var trimmedQuery: String { query.trimmingCharacters(in: .whitespacesAndNewlines) }

    var body: some View {
        MainTabPage(
            title: "本地库",
            search: PageSearch(text: $query, prompt: "搜索本地歌曲、专辑、歌手") { },
            onRefresh: { await library.scan() },
            headerAction: PageHeaderAction(title: "下载队列", systemImage: "arrow.down.circle",
                                           badge: downloads.jobs.filter(\.isActive).count) { showsDownloads = true }
        ) {
            if trimmedQuery.isEmpty {
                LocalLibraryCategoryList()
                if let issue = library.issue {
                    Label(issue, systemImage: "exclamationmark.triangle")
                        .font(.caption).foregroundStyle(DizzyPalette.accent)
                }
                if preview.isEmpty && (library.isImporting || library.isScanning) {
                    ContentSkeleton(layout: .grid)
                } else if preview.isEmpty {
                    ContentUnavailableView("还没有本地专辑", systemImage: "music.note.list",
                        description: Text("从「设置 › 音乐文件夹」导入音乐，下载的专辑也会显示在这里。"))
                } else {
                    NavigationLink(value: AppRoute.localAlbums) {
                        HStack(alignment: .firstTextBaseline) {
                            Text("专辑").font(.title2.bold())
                            Spacer()
                            Text("全部").font(.body).foregroundStyle(DizzyPalette.accent)
                        }
                        .contentShape(.rect)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("查看全部专辑")
                    LazyVGrid(columns: DizzyGrid.columns, alignment: .leading, spacing: 22) {
                        ForEach(preview.prefix(4)) { LocalLibraryAlbumPreviewCard(album: $0) }
                    }
                }
            } else {
                LocalLibrarySearchResults(query: trimmedQuery)
            }
        }
        .scrollDismissesKeyboard(.interactively)
        .sheet(isPresented: $showsDownloads) { DownloadQueueSheet() }
        .task(id: library.contentRevision) {
            let result = await LocalLibraryAlbumItem.prepare(library.visibleAlbums)
            guard !Task.isCancelled else { return }
            preview = result
        }
    }
}

/// 本地库的分类入口，与系统「音乐」的资料库列表一致。
private struct LocalLibraryCategoryList: View {
    @Environment(OfflineLibraryStore.self) private var library

    var body: some View {
        VStack(spacing: 0) {
            row("歌单", systemImage: "music.note.list", count: library.localPlaylists.count, route: .localPlaylists)
            Divider().padding(.leading, 42)
            row("专辑", systemImage: "square.stack", count: library.visibleAlbums.count, route: .localAlbums)
            Divider().padding(.leading, 42)
            row("歌曲", systemImage: "music.note", count: library.visibleAlbums.reduce(0) { $0 + $1.entries.count }, route: .localSongs)
            Divider().padding(.leading, 42)
            NavigationLink { MusicFolderView() } label: { label("音乐文件夹", systemImage: "folder", count: nil) }
                .buttonStyle(.plain)
            Divider().padding(.leading, 42)
        }
    }

    private func row(_ title: String, systemImage: String, count: Int, route: AppRoute) -> some View {
        NavigationLink(value: route) { label(title, systemImage: systemImage, count: count) }
            .buttonStyle(.plain)
    }

    private func label(_ title: String, systemImage: String, count: Int?) -> some View {
        HStack(spacing: 14) {
            Image(systemName: systemImage)
                .font(.title3)
                .foregroundStyle(DizzyPalette.accent)
                .frame(width: 28)
                .accessibilityHidden(true)
            Text(title).font(.title3).foregroundStyle(DizzyPalette.text)
            Spacer()
            if let count { Text("\(count)").foregroundStyle(DizzyPalette.mutedText).monospacedDigit() }
            Image(systemName: "chevron.right")
                .font(.footnote.weight(.semibold))
                .foregroundStyle(.tertiary)
                .accessibilityHidden(true)
        }
        .frame(minHeight: 50)
        .contentShape(.rect)
    }
}

/// 首页预览只负责打开专辑；多选与删除在「专辑」页里进行。
private struct LocalLibraryAlbumPreviewCard: View {
    let album: LocalLibraryAlbumItem

    var body: some View {
        NavigationLink(value: AppRoute.localAlbum(id: album.id)) {
            VStack(alignment: .leading, spacing: 6) {
                ArtworkImage(url: album.coverURL)
                Text(album.title).font(.subheadline.weight(.semibold)).foregroundStyle(DizzyPalette.text).lineLimit(1)
                Text("\(album.artist) · \(album.count) 首").font(.caption).foregroundStyle(DizzyPalette.mutedText).lineLimit(1)
            }
            .multilineTextAlignment(.leading)
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .prefetchAlbumArtwork(url: album.coverURL)
    }
}

/// 在本地专辑与曲目中按标题、歌手和专辑名查找。
private struct LocalLibrarySearchResults: View {
    let query: String
    @Environment(OfflineLibraryStore.self) private var library
    @Environment(PlayerStore.self) private var player

    var body: some View {
        let albums = library.visibleAlbums.filter { $0.title.localizedStandardContains(query) || $0.artist.localizedStandardContains(query) }
        let tracks = library.visibleAlbums.flatMap(\.tracks).filter {
            $0.title.localizedStandardContains(query) || $0.artists.localizedStandardContains(query) || $0.albumTitle.localizedStandardContains(query)
        }
        if albums.isEmpty && tracks.isEmpty {
            ContentUnavailableView.search(text: query)
        }
        if !albums.isEmpty {
            Text("专辑").font(.title3.bold())
            ForEach(albums.prefix(6)) { album in
                NavigationLink(value: AppRoute.localAlbum(id: album.id)) {
                    HStack(spacing: 12) {
                        ArtworkImage(url: album.coverURL, cornerRadius: 6).frame(width: 52, height: 52)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(album.title).foregroundStyle(DizzyPalette.text).lineLimit(1)
                            Text(album.artist).font(.subheadline).foregroundStyle(DizzyPalette.mutedText).lineLimit(1)
                        }
                        Spacer()
                    }
                    .contentShape(.rect)
                }
                .buttonStyle(.plain)
            }
        }
        if !tracks.isEmpty {
            Text("歌曲").font(.title3.bold())
            ForEach(Array(tracks.prefix(50).enumerated()), id: \.element.id) { index, track in
                LocalSongRow(track: track) { player.play(Array(tracks.prefix(50)), startAt: index) }
            }
        }
    }
}

/// 一首本地歌曲：封面、标题、歌手 · 专辑。
struct LocalSongRow: View {
    let track: Track
    let play: () -> Void
    @Environment(PlayerStore.self) private var player

    var body: some View {
        Button(action: play) {
            HStack(spacing: 12) {
                ArtworkImage(url: track.coverURL, cornerRadius: 6).frame(width: 44, height: 44)
                VStack(alignment: .leading, spacing: 2) {
                    Text(track.title)
                        .foregroundStyle(player.currentTrack?.id == track.id ? DizzyPalette.accent : DizzyPalette.text)
                        .lineLimit(1)
                    Text([track.artists, track.albumTitle].filter { !$0.isEmpty }.joined(separator: " · "))
                        .font(.subheadline).foregroundStyle(DizzyPalette.mutedText).lineLimit(1)
                }
                Spacer(minLength: 0)
            }
            .frame(minHeight: 52)
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(track.title)，\(track.artists)")
    }
}

struct LocalPlaylistsPage: View {
    var body: some View {
        ScrollView { LocalPlaylistsView().padding(.horizontal, 20).padding(.vertical, 8) }
            .dizzyPageBackground()
            .navigationTitle("歌单")
            .navigationBarTitleDisplayMode(.large)
    }
}

struct LocalSongsPage: View {
    @Environment(OfflineLibraryStore.self) private var library
    @Environment(PlayerStore.self) private var player

    var body: some View {
        let tracks = library.visibleAlbums.flatMap(\.tracks)
            .sorted { $0.title.localizedStandardCompare($1.title) == .orderedAscending }
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 4) {
                if tracks.isEmpty {
                    ContentUnavailableView("还没有本地歌曲", systemImage: "music.note")
                } else {
                    AlbumPlaybackActions(isEmpty: false) { shuffled in
                        player.play(tracks, startAt: shuffled ? Int.random(in: tracks.indices) : 0)
                        if player.isShuffled != shuffled { player.toggleShuffle() }
                    }
                    .padding(.bottom, 12)
                    ForEach(Array(tracks.enumerated()), id: \.element.id) { index, track in
                        LocalSongRow(track: track) { player.play(tracks, startAt: index) }
                    }
                }
            }
            .padding(.horizontal, 20).padding(.vertical, 8)
        }
        .dizzyPageBackground()
        .navigationTitle("歌曲")
        .navigationBarTitleDisplayMode(.large)
    }
}

/// 全部本地专辑：长按可多选删除。
struct LocalAlbumsPage: View {
    @Environment(OfflineLibraryStore.self) private var library
    @State private var selection = LocalAlbumSelection()
    @State private var items: [LocalLibraryAlbumItem] = []
    @State private var deletingAlbums: [LocalLibraryAlbumItem]?
    @State private var isDeleting = false
    @State private var deletionFailure: String?

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 20) {
                if items.isEmpty && (library.isImporting || library.isScanning) {
                    ContentSkeleton(layout: .grid)
                } else if items.isEmpty {
                    ContentUnavailableView("还没有本地专辑", systemImage: "music.note.list",
                        description: Text("从「设置 › 音乐文件夹」导入音乐，下载的专辑也会显示在这里。"))
                } else {
                    LazyVGrid(columns: DizzyGrid.columns, alignment: .leading, spacing: 22) {
                        ForEach(items) { album in
                            LocalLibraryAlbumCard(album: album, selection: selection, isDeleting: isDeleting) {
                                deletingAlbums = [album]
                            }
                        }
                    }
                }
            }
            .padding(.horizontal, 20).padding(.vertical, 8)
        }
        .refreshable { await library.scan() }
        .dizzyPageBackground()
        .navigationTitle("专辑")
        .navigationBarTitleDisplayMode(.large)
        .safeAreaInset(edge: .bottom, spacing: 0) {
            if selection.isSelecting {
                LocalAlbumSelectionBar(selection: selection, ids: Set(items.map(\.id)), isDeleting: isDeleting) { ids in
                    deletingAlbums = items.filter { ids.contains($0.id) }
                }
                .padding(.horizontal, 20)
                .padding(.vertical, 12)
            }
        }
        .confirmationDialog("删除专辑？", item: $deletingAlbums, titleVisibility: .visible) { albums in
            Button("删除", role: .destructive) { delete(albums) }
            Button("取消", role: .cancel) { }
        } message: { albums in
            Text("将删除 \(albums.count) 张专辑中的 \(albums.reduce(0) { $0 + $1.count }) 首本地音频文件，此操作无法撤销。")
        }
        .alert("删除失败", item: $deletionFailure) { _ in
            Button("好", role: .cancel) { }
        } message: { Text($0) }
        // File canonicalization and sorting happen only when the library changes, off the main actor.
        .task(id: library.contentRevision) {
            let result = await LocalLibraryAlbumItem.prepare(library.visibleAlbums)
            guard !Task.isCancelled else { return }
            items = result
            selection.ids.formIntersection(result.map(\.id))
            if result.isEmpty { selection.finish() }
        }
    }

    private func delete(_ albums: [LocalLibraryAlbumItem]) {
        guard !isDeleting else { return }
        isDeleting = true
        Task {
            defer { isDeleting = false }
            do {
                try await library.deleteAlbums(ids: Set(albums.map(\.id)))
                selection.ids.subtract(albums.map(\.id))
                if selection.ids.isEmpty { selection.finish() }
            } catch { deletionFailure = error.localizedDescription }
        }
    }
}

/// Selection is observed by cards and the control bar, not by the library's grid-building body.
@Observable private final class LocalAlbumSelection {
    var isSelecting = false
    var ids: Set<String> = []

    func start(_ id: String) { ids = [id]; isSelecting = true }
    func toggle(_ id: String) { if !ids.insert(id).inserted { ids.remove(id) } }
    func finish() { isSelecting = false; ids.removeAll() }
}

nonisolated private struct LocalLibraryAlbumItem: Identifiable, Sendable {
    let id: String
    let title: String
    let artist: String
    let coverURL: URL?
    let count: Int

    @concurrent static func prepare(_ albums: [LocalAlbum]) async -> [Self] {
        albums.map { album in
            Self(id: album.id, title: album.title, artist: album.artist, coverURL: album.coverURL, count: album.entries.count)
        }.sorted { $0.title.localizedStandardCompare($1.title) == .orderedAscending }
    }
}

private struct LocalAlbumSelectionBar: View {
    let selection: LocalAlbumSelection
    let ids: Set<String>
    let isDeleting: Bool
    let delete: (Set<String>) -> Void

    var body: some View {
        GlassEffectContainer(spacing: 12) {
            HStack(spacing: 12) {
                HStack(spacing: 12) {
                    Text("已选 \(selection.ids.count)").monospacedDigit()
                    Button(selection.ids == ids ? "取消全选" : "全选") {
                        selection.ids = selection.ids == ids ? [] : ids
                    }
                    .frame(minHeight: 44)
                    .disabled(isDeleting || ids.isEmpty)
                }
                .font(.subheadline)
                .padding(.horizontal, 16)
                .glassEffect(.regular, in: .capsule)
                Spacer(minLength: 0)
                Button("删除", systemImage: "trash", role: .destructive) { delete(selection.ids) }
                    .labelStyle(.iconOnly)
                    .frame(minWidth: 44, minHeight: 44)
                    .buttonStyle(.glass)
                    .tint(.red)
                    .disabled(selection.ids.isEmpty || isDeleting)
                Button("完成") { selection.finish() }
                    .buttonStyle(.glassProminent)
                    .controlSize(.large)
                    .disabled(isDeleting)
            }
        }
    }
}

private struct LocalLibraryAlbumCard: View {
    let album: LocalLibraryAlbumItem
    let selection: LocalAlbumSelection
    let isDeleting: Bool
    let delete: () -> Void
    @Environment(\.openRoute) private var openRoute
    private var isSelected: Bool { selection.ids.contains(album.id) }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            // Remove the context-menu recognizer entirely during selection, including its preview.
            if selection.isSelecting {
                coverButton
            } else {
                coverButton
                    .contentShape(.contextMenuPreview, .rect(cornerRadius: 10))
                    .contextMenu {
                        Button("多选", systemImage: "checkmark.circle") { selection.start(album.id) }
                            .disabled(isDeleting)
                        Button("删除", systemImage: "trash", role: .destructive, action: delete)
                            .disabled(isDeleting)
                    } preview: {
                        ArtworkImage(url: album.coverURL).frame(width: 260, height: 260)
                    }
            }
            Button(action: activate) {
                VStack(alignment: .leading, spacing: 6) {
                    Text(album.title).font(.subheadline.weight(.semibold)).lineLimit(2)
                    Text(album.artist).font(.caption).foregroundStyle(DizzyPalette.mutedText).lineLimit(1)
                    Text("\(album.count) 首").font(.caption).foregroundStyle(DizzyPalette.mutedText)
                }
                .multilineTextAlignment(.leading)
                .contentShape(.rect)
            }
            .buttonStyle(.plain)
        }
        .prefetchAlbumArtwork(url: album.coverURL)
    }

    private var coverButton: some View {
        Button(action: activate) {
            ArtworkImage(url: album.coverURL)
                .overlay {
                    if isSelected {
                        RoundedRectangle(cornerRadius: 10).fill(DizzyPalette.accent.opacity(0.22))
                        RoundedRectangle(cornerRadius: 10).strokeBorder(DizzyPalette.accent, lineWidth: 3)
                    }
                }
                .overlay(alignment: .topTrailing) {
                    if selection.isSelecting {
                        Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                            .font(.title3.weight(.semibold))
                            .foregroundStyle(isSelected ? DizzyPalette.accent : .white)
                            .background(.black.opacity(0.35), in: Circle())
                            .padding(8)
                    }
                }

        }
        .buttonStyle(.plain)
        .contentShape(.interaction, .rect(cornerRadius: 10))
        .accessibilityLabel(album.title)
        .accessibilityValue(selection.isSelecting ? (isSelected ? "已选择" : "未选择") : "")
    }

    private func activate() {
        if selection.isSelecting {
            guard !isDeleting else { return }
            selection.toggle(album.id)
        } else { openRoute(.localAlbum(id: album.id)) }
    }
}

struct LocalAlbumDetailView: View {
    let id: String
    @State private var editing: AudioTagEditTarget?
    @State private var playlistTrack: Track?
    @State private var batchAlbum: LocalAlbum?
    @Environment(OfflineLibraryStore.self) private var library
    @Environment(PlayerStore.self) private var player

    var body: some View {
        AlbumDetailScrollView(artworkURL: library.localAlbum(id: id)?.coverURL) {
            if let album = library.localAlbum(id: id) {
                LazyVStack(alignment: .leading, spacing: 0) {
                    AlbumHero(artworkURL: album.coverURL, title: album.title,
                              metadata: "\(album.tracks.count) 首") {
                        Text(album.artist)
                    } actions: {
                        AlbumPlaybackActions(isEmpty: album.tracks.isEmpty) { shuffled in
                            guard !album.tracks.isEmpty else { return }
                            player.play(album.tracks, startAt: shuffled ? Int.random(in: album.tracks.indices) : 0)
                            if player.isShuffled != shuffled { player.toggleShuffle() }
                        }
                    }
                    ForEach(Array(Set(album.entries.map(\.discNumber))).sorted(), id: \.self) { disc in
                        if Set(album.entries.map(\.discNumber)).count > 1 {
                            Text("Disc \(disc)").font(.headline).padding(.vertical, 12)
                        }
                        let entries = album.entries.filter { $0.discNumber == disc }
                        ForEach(entries, id: \.track.id) { entry in
                            AlbumTrackRow(track: entry.track, editTags: {
                                editing = AudioTagEditTarget(track: entry.track, url: entry.fileURL)
                            }, additionalActions: [AlbumRowAction(id: "playlist", title: "加入歌单", systemImage: "text.badge.plus", perform: { playlistTrack = entry.track })]) {
                                if let index = album.tracks.firstIndex(where: { $0.id == entry.track.id }) {
                                    player.play(album.tracks, startAt: index)
                                }
                            }
                            .padding(.horizontal, -20)
                        }
                    }
                }
                .padding(.horizontal, 20).padding(.bottom, 32)
            } else {
                ContentUnavailableView("找不到本地专辑", systemImage: "folder.badge.questionmark",
                                       description: Text("专辑可能已被移动或删除，请下拉本地库重新扫描。"))
            }
        }
        .dizzyPageBackground()
        .sheet(item: $playlistTrack) { LocalPlaylistPicker(track: $0) }
        .sheet(item: $editing) { AudioTagEditorSheet(target: $0) }
        .sheet(item: $batchAlbum) { BatchAudioTagEditorSheet(album: $0) }
        .safeAreaPadding(.top, 5)
        .navigationTitle("")
        .toolbar(.visible, for: .navigationBar)
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(.hidden, for: .navigationBar)
        .toolbar {
            if let album = library.localAlbum(id: id) {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("批量编辑", systemImage: "square.and.pencil") { batchAlbum = album }
                }
            }
        }
    }
}
