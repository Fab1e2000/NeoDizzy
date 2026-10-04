import AppKit
import SwiftUI

/// 本地专辑：在标题右侧切换「专辑」网格与「歌曲」表格。下拉刷新换成 ⌘R 与「重新扫描」。
struct LocalLibraryPage: View {
    @Environment(OfflineLibraryStore.self) private var library
    @AppStorage("localLibrary.showsSongs") private var showsSongs = false

    private var albums: [LocalAlbum] {
        library.localAlbums.sorted { $0.title.localizedStandardCompare($1.title) == .orderedAscending }
    }

    var body: some View {
        Group {
            if albums.isEmpty {
                PageScroll(title: MainTab.localLibrary.title) {
                    if library.isScanning {
                        DelayedProgress()
                    } else {
                        ContentUnavailableView {
                            Label("还没有本地专辑", systemImage: "square.stack")
                        } description: {
                            Text("添加音乐文件夹后，每个直接包含音频的文件夹都会成为一张专辑。下载的专辑也会自动显示在这里。")
                        } actions: {
                            AddFolderButton()
                        }
                        .padding(.vertical, 50)
                    }
                    issue
                }
            } else if showsSongs {
                VStack(alignment: .leading, spacing: 12) {
                    PageTitleRow(title: MainTab.localLibrary.title) { modePicker }
                        .pageContentFrame()
                        .padding(.top, 12)
                    LocalSongsTable(albums: albums)
                }
            } else {
                PageScroll(title: MainTab.localLibrary.title) {
                    modePicker
                } content: {
                    issue
                    LazyVGrid(columns: PageMetrics.gridColumns, alignment: .leading, spacing: PageMetrics.gridSpacing) {
                        ForEach(albums) { album in
                            LocalAlbumCard(album: album)
                        }
                    }
                }
            }
        }
        .navigationTitle(MainTab.localLibrary.title)
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button { Task { await library.scan() } } label: {
                    // 保留同一工具栏项和固定尺寸，扫描时不插入额外控件挤动刷新按钮。
                    Image(systemName: "arrow.clockwise")
                        .frame(width: 20, height: 20)
                        .opacity(library.isScanning ? 0 : 1)
                        .overlay {
                            if library.isScanning {
                                ProgressView()
                                    .controlSize(.small)
                                    .frame(width: 20, height: 20)
                            }
                        }
                }
                .disabled(library.isScanning)
                .accessibilityLabel(library.isScanning ? "正在扫描本地库" : "重新扫描本地库")
                .help(library.isScanning ? "正在扫描本地库" : "重新扫描本地库")
            }
        }
        .pageRefresh { await library.scan() }
    }

    private var modePicker: some View {
        Picker("显示", selection: $showsSongs) {
            Text("专辑").tag(false)
            Text("歌曲").tag(true)
        }
        .pickerStyle(.segmented)
        .labelsHidden()
        .fixedSize()
    }

    @ViewBuilder private var issue: some View {
        if let issue = library.issue {
            Label(issue, systemImage: "exclamationmark.triangle")
                .foregroundStyle(Color.dizzyGold)
        }
    }
}

/// 添加扫描目录（文件 → 添加音乐文件夹…）。
struct AddFolderButton: View {
    @Environment(OfflineLibraryStore.self) private var library
    @State private var failure: String?

    var body: some View {
        VStack(spacing: 6) {
            Button("添加音乐文件夹…") {
                Task {
                    guard let url = await FolderPanel.chooseFolder(message: String(localized: "选择要加入本地库的音乐文件夹。只读取音乐文件，不会修改它们。"),
                                                                   prompt: String(localized: "添加")) else { return }
                    do { try await library.addScanFolder(url); failure = nil } catch { failure = error.localizedDescription }
                }
            }
            .buttonStyle(.borderedProminent)
            .disabled(library.isScanning)
            if let failure { Text(failure).foregroundStyle(DizzyPalette.danger) }
        }
    }
}

private struct LocalAlbumCard: View {
    let album: LocalAlbum
    @Environment(MacAppModel.self) private var model

    var body: some View {
        AlbumCard(title: album.title, subtitle: album.artist, caption: String(localized: "\(album.tracks.count) 首"),
                  coverURL: album.coverURL, route: .localAlbum(id: album.id),
                  play: { shuffled in model.play(album.tracks, shuffled: shuffled) }) {
            if let folder = album.entries.first?.fileURL.deletingLastPathComponent() {
                Button("在访达中显示", systemImage: "folder") { NSWorkspace.shared.activateFileViewerSelecting([folder]) }
                Divider()
            }
        }
    }
}

/// 全部本地歌曲的原生表格，可按列排序，双击播放。
private struct LocalSongsTable: View {
    let albums: [LocalAlbum]
    @Environment(PlayerStore.self) private var player
    @State private var selection = Set<String>()
    @State private var sortOrder = [KeyPathComparator(\SongRow.album), KeyPathComparator(\SongRow.order)]

    struct SongRow: Identifiable {
        let id: String
        let track: Track
        let title: String
        let artist: String
        let album: String
        let duration: Double
        /// 专辑内的原始顺序（碟号、曲号）。
        let order: Int
        let albumTracks: [Track]
        let index: Int
    }

    private var rows: [SongRow] {
        albums.flatMap { album in
            album.tracks.enumerated().map { index, track in
                SongRow(id: track.id, track: track, title: track.title, artist: track.artists, album: album.title,
                        duration: track.duration ?? 0, order: index, albumTracks: album.tracks, index: index)
            }
        }
        .sorted(using: sortOrder)
    }

    var body: some View {
        let rows = rows
        Table(rows, selection: $selection, sortOrder: $sortOrder) {
            TableColumn("") { row in
                if player.currentTrack?.id == row.id {
                    Image(systemName: "speaker.wave.2.fill").foregroundStyle(Color.dizzyGold)
                }
            }
            .width(18)
            TableColumn("标题", value: \.title)
            TableColumn("歌手", value: \.artist)
            TableColumn("专辑", value: \.album)
            TableColumn("时长", value: \.duration) { row in
                Text(row.duration > 0 ? TimeFormat.clock(row.duration) : "").monospacedDigit().foregroundStyle(.secondary)
            }
            .width(min: 50, ideal: 60, max: 80)
        }
        .contextMenu(forSelectionType: String.self) { ids in
            if let row = rows.first(where: { ids.contains($0.id) }) {
                Button("播放", systemImage: "play") { play(row) }
            }
        } primaryAction: { ids in
            if let row = rows.first(where: { ids.contains($0.id) }) { play(row) }
        }
    }

    private func play(_ row: SongRow) {
        player.play(row.albumTracks, startAt: row.index)
    }
}

/// 本地专辑页：按碟号分组的曲目，单曲编辑标签和批量编辑 FLAC。
struct LocalAlbumPage: View {
    let id: String
    @Environment(MacAppModel.self) private var model
    @Environment(OfflineLibraryStore.self) private var library
    @Environment(PlayerStore.self) private var player
    @State private var editing: AudioTagEditTarget?
    @State private var batchAlbum: LocalAlbum?

    var body: some View {
        Group {
            if let album = library.localAlbum(id: id) {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 26) {
                        AlbumHeader(artworkURL: album.coverURL, title: album.title,
                                    metadata: String(localized: "本地专辑 · \(album.tracks.count) 首")) {
                            Text(AlbumHeaderMetrics.condensedArtists(album.artist))
                                .help(album.artist)
                        } actions: {
                            AlbumPlayButtons(isEmpty: album.tracks.isEmpty) { shuffled in model.play(album.tracks, shuffled: shuffled) }
                            Button { batchAlbum = album } label: { HeaderSecondaryLabel(title: "批量编辑", systemImage: "square.and.pencil") }
                                .buttonStyle(HeaderSecondaryButtonStyle())
                                .help("统一修改 FLAC 曲目的歌手、专辑名、年份、流派或封面")
                            if let folder = album.entries.first?.fileURL.deletingLastPathComponent() {
                                Button { NSWorkspace.shared.activateFileViewerSelecting([folder]) } label: {
                                    HeaderSecondaryLabel(title: "在访达中显示", systemImage: "folder")
                                }
                                .buttonStyle(HeaderSecondaryButtonStyle())
                            }
                        }
                        let discs = Array(Set(album.entries.map(\.discNumber))).sorted()
                        ForEach(discs, id: \.self) { disc in
                            VStack(alignment: .leading, spacing: 8) {
                                if discs.count > 1 {
                                    Text("Disc \(disc)").font(.headline).foregroundStyle(.secondary)
                                }
                                let entries = album.entries.filter { $0.discNumber == disc }
                                TrackList(tracks: entries.map(\.track), albumArtist: album.artist) { index in
                                    let track = entries[index].track
                                    if let position = album.tracks.firstIndex(where: { $0.id == track.id }) {
                                        player.play(album.tracks, startAt: position)
                                    }
                                } rowMenu: { track in
                                    if let entry = entries.first(where: { $0.track.id == track.id }) {
                                        Button("编辑音乐标签…", systemImage: "pencil") {
                                            editing = AudioTagEditTarget(track: entry.track, url: entry.fileURL)
                                        }
                                        Button("在访达中显示", systemImage: "folder") {
                                            NSWorkspace.shared.activateFileViewerSelecting([entry.fileURL])
                                        }
                                    }
                                }
                                .padding(.horizontal, -10)
                            }
                        }
                        TrackListFooter(tracks: album.tracks)
                    }
                    .pageContentFrame()
                    .padding(.top, 16)
                    .padding(.bottom, 28)
                }
                .navigationTitle(album.title)
            } else {
                ContentUnavailableView("找不到本地专辑", systemImage: "folder.badge.questionmark",
                                       description: Text("请检查扫描目录授权和音乐文件，然后重新扫描。"))
            }
        }
        .sheet(item: $editing) { TagEditorSheet(target: $0) }
        .sheet(item: $batchAlbum) { BatchTagEditorSheet(album: $0) }
        .pageRefresh { await library.scan() }
    }
}

/// 要编辑标签的一首本地曲目。
struct AudioTagEditTarget: Identifiable {
    let track: Track
    let url: URL
    var id: String { url.path }
}
