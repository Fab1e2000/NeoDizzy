import SwiftUI

struct LocalLibraryView: View {
    @Environment(OfflineLibraryStore.self) private var library
    @State private var showsPlaylists = false
    @State private var showsDownloads = false
    @State private var selection = LocalAlbumSelection()
    @State private var items: [LocalLibraryAlbumItem] = []
    @State private var deletingAlbums: [LocalLibraryAlbumItem]?
    @State private var isDeleting = false
    @State private var deletionFailure: String?

    var body: some View {
        VStack(spacing: 16) {
            PageHeader(title: "本地库", action: PageHeaderAction(
                title: "下载队列", systemImage: "arrow.down.circle", perform: { showsDownloads = true }
            ))
            .padding(.horizontal, 20)
            Picker("本地库", selection: $showsPlaylists.animation(.snappy(duration: 0.25))) {
                Text("专辑").tag(false)
                Text("歌单").tag(true)
            }
            .pickerStyle(.segmented)
            .padding(.horizontal, 20)
            // Same paging mechanism as NeoBili VideoPage.sectionPages: no TabView page-indicator inset.
            ScrollView(.horizontal) {
                LazyHStack(spacing: 0) {
                    ScrollView {
                        LazyVStack(alignment: .leading, spacing: 20) {
                            if items.isEmpty && (library.isImporting || library.isScanning) {
                                ContentSkeleton(layout: .grid)
                            }
                            if let issue = library.issue {
                                Label(issue, systemImage: "exclamationmark.triangle")
                                    .font(.caption).foregroundStyle(DizzyPalette.accent)
                            }
                            if items.isEmpty && !library.isScanning && !library.isImporting {
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
                        }.padding(.horizontal, 20).padding(.bottom, 24)
                    }
                    .containerRelativeFrame(.horizontal)
                    .id(false)
                    ScrollView {
                        LocalPlaylistsView().padding(.horizontal, 20).padding(.bottom, 24)
                    }
                    .containerRelativeFrame(.horizontal)
                    .id(true)
                }.scrollTargetLayout()
            }
            .scrollPosition(id: Binding<Bool?>(get: { showsPlaylists }, set: { if let value = $0 { showsPlaylists = value } }))
            .scrollTargetBehavior(.paging)
            .scrollIndicators(.hidden)
        }
        .dizzyPageBackground()
        .contentPageNavigationBar()
        .safeAreaInset(edge: .bottom, spacing: 0) {
            if selection.isSelecting {
                LocalAlbumSelectionBar(selection: selection, ids: Set(items.map(\.id)), isDeleting: isDeleting) { ids in
                    deletingAlbums = items.filter { ids.contains($0.id) }
                }
                .padding(.horizontal, 20)
                .padding(.vertical, 12)
            }
        }
        .sheet(isPresented: $showsDownloads) { DownloadQueueSheet() }
        .confirmationDialog("删除专辑？", item: $deletingAlbums, titleVisibility: .visible) { albums in
            Button("删除", role: .destructive) { delete(albums) }
            Button("取消", role: .cancel) { }
        } message: { albums in
            Text("将删除 \(albums.count) 张专辑中的 \(albums.reduce(0) { $0 + $1.count }) 首本地音频文件，此操作无法撤销。")
        }
        .alert("删除失败", item: $deletionFailure) { _ in
            Button("好", role: .cancel) { }
        } message: { Text($0) }
        .onChange(of: showsPlaylists) { _, _ in selection.finish() }
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
