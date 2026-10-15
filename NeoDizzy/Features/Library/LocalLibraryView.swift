import SwiftUI

/// 资料库首页：本地文件和手动加入的在线歌曲、专辑、歌单放在一起，按来源筛选。
struct LocalLibraryView: View {
    @Environment(OfflineLibraryStore.self) private var library
    @Environment(SavedLibraryStore.self) private var saved
    @Environment(DownloadStore.self) private var downloads
    @State private var showsDownloads = false
    @State private var query = ""
    @State private var filter = LibraryOriginFilter.all
    @State private var localRecent: [RecentLibraryItem] = []
    private var trimmedQuery: String { query.trimmingCharacters(in: .whitespacesAndNewlines) }

    var body: some View {
        MainTabPage(
            title: "资料库",
            search: PageSearch(text: $query, prompt: "搜索资料库") { },
            onRefresh: { await library.scan() },
            headerAction: PageHeaderAction(title: "下载队列", systemImage: "arrow.down.circle",
                                           badge: downloads.jobs.filter(\.isActive).count) { showsDownloads = true }
        ) {
            if trimmedQuery.isEmpty {
                LibraryOriginPicker(selection: $filter)
                LibraryCategoryList(filter: filter)
                if let issue = library.issue, filter.includes(.local) {
                    Label(issue, systemImage: "exclamationmark.triangle")
                        .font(.caption).foregroundStyle(DizzyPalette.accent)
                }
                let recent = recentItems
                if recent.isEmpty && (library.isImporting || library.isScanning) {
                    ContentSkeleton(layout: .grid)
                } else if recent.isEmpty {
                    ContentUnavailableView("资料库还是空的", systemImage: "music.note.list",
                        description: Text("导入音乐，或在网易云、DizzyLab 的歌曲和专辑菜单里选「加入资料库」。"))
                } else {
                    Text("最近添加").font(.title2.bold()).accessibilityAddTraits(.isHeader)
                    LazyVGrid(columns: DizzyGrid.columns, alignment: .leading, spacing: 22) {
                        ForEach(recent) { LibraryShelfCard(item: $0, showsOrigin: filter == .all) }
                    }
                }
            } else {
                LibrarySearchResults(query: trimmedQuery)
            }
        }
        .scrollDismissesKeyboard(.interactively)
        .sheet(isPresented: $showsDownloads) { DownloadQueueSheet() }
        .task(id: library.contentRevision) {
            let result = await RecentLibraryItem.prepare(albums: library.visibleAlbums, playlists: library.localPlaylists)
            guard !Task.isCancelled else { return }
            localRecent = result
        }
    }

    private var recentItems: [LibraryShelfItem] {
        let local = filter.includes(.local) ? localRecent.map(\.collection) : []
        let online = saved.items.filter { $0.kind != .song }.compactMap(LibraryShelfItem.init(saved:))
            .filter { filter.includes($0.origin) }
        return Array((local + online).sorted { $0.addedAt > $1.addedAt }.prefix(RecentLibraryItem.limit))
    }
}

/// 来源筛选：全部 · 本地 · 网易云 · DizzyLab。
struct LibraryOriginPicker: View {
    @Binding var selection: LibraryOriginFilter

    var body: some View {
        DiscoveryCategoryPicker(selection: $selection, options: LibraryOriginFilter.choices.map { ($0, $0.label) })
    }
}

/// 资料库的分类入口，与系统「音乐」的资料库列表一致；数量跟随来源筛选。
private struct LibraryCategoryList: View {
    let filter: LibraryOriginFilter
    @Environment(OfflineLibraryStore.self) private var library
    @Environment(SavedLibraryStore.self) private var saved

    var body: some View {
        let contents = LibraryContents(library: library, saved: saved)
        let songs = contents.songs(filter)
        VStack(spacing: 0) {
            row("歌单", systemImage: "music.note.list", count: contents.playlists(filter).count, route: .libraryPlaylists(filter))
            Divider().padding(.leading, 42)
            row("专辑", systemImage: "square.stack", count: contents.albums(filter).count, route: .libraryAlbums(filter))
            Divider().padding(.leading, 42)
            row("歌曲", systemImage: "music.note", count: songs.count, route: .librarySongs(filter))
            Divider().padding(.leading, 42)
            row("歌手", systemImage: "music.microphone", count: LibraryContents.artists(in: songs).count, route: .libraryArtists(filter))
            Divider().padding(.leading, 42)
            if filter.includes(.local) {
                NavigationLink { MusicFolderView() } label: { label("音乐文件夹", systemImage: "folder", count: nil) }
                    .buttonStyle(.plain)
                Divider().padding(.leading, 42)
            }
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

/// 一首资料库歌曲：本地文件，或手动加入的在线歌曲。
struct LibrarySong: Identifiable {
    let track: Track
    let origin: LibraryOrigin
    /// 在线歌曲在资料库索引里的 ID，用来移除。
    let savedID: String?
    var id: String { track.id }
}

/// 一张专辑或一个歌单，本地的或手动加入的在线条目。
struct LibraryShelfItem: Identifiable {
    let id: String
    let title: String
    let subtitle: String
    let coverURL: URL?
    let origin: LibraryOrigin
    let route: AppRoute
    let addedAt: Date
    let savedID: String?

    init(id: String, title: String, subtitle: String, coverURL: URL?, origin: LibraryOrigin, route: AppRoute,
         addedAt: Date, savedID: String? = nil) {
        self.id = id; self.title = title; self.subtitle = subtitle; self.coverURL = coverURL
        self.origin = origin; self.route = route; self.addedAt = addedAt; self.savedID = savedID
    }

    /// 在线专辑与歌单打开各自平台的页面。
    init?(saved item: SavedLibraryItem) {
        guard let origin = LibraryOrigin(providerID: item.providerID) else { return nil }
        let route: AppRoute
        switch (origin, item.kind) {
        case (.netease, .album): guard let id = Int(item.itemID) else { return nil }; route = .netease(.album(id))
        case (.netease, .playlist): guard let id = Int(item.itemID) else { return nil }; route = .netease(.playlist(id))
        case (.dizzylab, .album): route = .disc(id: item.itemID)
        default: return nil
        }
        let kind = item.kind == .album ? String(localized: "专辑") : String(localized: "歌单")
        self.init(id: item.id, title: item.title, subtitle: "\(item.subtitle) · \(kind)", coverURL: item.coverURL,
                  origin: origin, route: route, addedAt: item.addedAt, savedID: item.id)
    }
}

/// 把本地库和资料库索引合成一份内容，按来源筛选。
@MainActor
struct LibraryContents {
    let library: OfflineLibraryStore
    let saved: SavedLibraryStore

    func songs(_ filter: LibraryOriginFilter) -> [LibrarySong] {
        var songs: [LibrarySong] = []
        if filter.includes(.local) {
            songs += library.visibleAlbums.flatMap(\.tracks).map { LibrarySong(track: $0, origin: .local, savedID: nil) }
        }
        for item in saved.items(of: .song) {
            guard let track = item.track, let origin = LibraryOrigin(providerID: item.providerID), filter.includes(origin) else { continue }
            songs.append(LibrarySong(track: track, origin: origin, savedID: item.id))
        }
        return songs.sorted { $0.track.title.localizedStandardCompare($1.track.title) == .orderedAscending }
    }

    func albums(_ filter: LibraryOriginFilter) -> [LibraryShelfItem] {
        let local = filter.includes(.local) ? library.visibleAlbums.map { album in
            LibraryShelfItem(id: album.id, title: album.title, subtitle: album.artist, coverURL: album.coverURL,
                              origin: .local, route: .localAlbum(id: album.id), addedAt: .distantPast)
        } : []
        return local + online(.album, filter)
    }

    func playlists(_ filter: LibraryOriginFilter) -> [LibraryShelfItem] {
        let local = filter.includes(.local) ? library.localPlaylists.map { playlist in
            LibraryShelfItem(id: playlist.id, title: playlist.title, subtitle: "\(playlist.tracks.count) 首", coverURL: playlist.coverURL,
                              origin: .local, route: .localPlaylist(id: playlist.id), addedAt: .distantPast)
        } : []
        return local + online(.playlist, filter)
    }

    func online(_ kind: SavedLibraryItem.Kind, _ filter: LibraryOriginFilter) -> [LibraryShelfItem] {
        saved.items(of: kind).compactMap(LibraryShelfItem.init(saved:)).filter { filter.includes($0.origin) }
            .sorted { $0.title.localizedStandardCompare($1.title) == .orderedAscending }
    }

    /// 歌手名与歌曲数，按名称排序。多人署名按逗号、斜杠和顿号拆开。
    static func artists(in songs: [LibrarySong]) -> [(name: String, count: Int)] {
        var counts: [String: Int] = [:]
        for song in songs {
            for name in artistNames(song.track) { counts[name, default: 0] += 1 }
        }
        return counts.map { ($0.key, $0.value) }.sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }

    static func artistNames(_ track: Track) -> [String] {
        let names = track.artists.split(whereSeparator: { ",，/、".contains($0) })
            .map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
        return names.isEmpty ? [String(localized: "未知歌手")] : names
    }
}

/// 封面角落或歌曲副标题前的来源标记。
struct LibraryOriginBadge: View {
    let origin: LibraryOrigin
    var onArtwork = false

    var body: some View {
        Text(origin.label)
            .font(.caption2.weight(.semibold))
            .foregroundStyle(onArtwork ? Color.white : DizzyPalette.mutedText)
            .padding(.horizontal, onArtwork ? 7 : 5)
            .padding(.vertical, onArtwork ? 3 : 1)
            .background {
                if onArtwork {
                    Capsule().fill(.black.opacity(0.6))
                } else {
                    RoundedRectangle(cornerRadius: 4).strokeBorder(DizzyPalette.mutedText.opacity(0.6), lineWidth: 1)
                }
            }
            .accessibilityLabel("来源：\(origin.label)")
    }
}

/// 专辑或歌单卡片；在线条目长按可从资料库移除。
struct LibraryShelfCard: View {
    let item: LibraryShelfItem
    var showsOrigin = true
    @Environment(SavedLibraryStore.self) private var saved

    var body: some View {
        let link = NavigationLink(value: item.route) {
            VStack(alignment: .leading, spacing: 6) {
                ArtworkImage(url: item.coverURL)
                    .overlay(alignment: .bottomLeading) {
                        if showsOrigin { LibraryOriginBadge(origin: item.origin, onArtwork: true).padding(7) }
                    }
                Text(item.title).font(.subheadline.weight(.semibold)).foregroundStyle(DizzyPalette.text).lineLimit(1)
                Text(item.subtitle).font(.caption).foregroundStyle(DizzyPalette.mutedText).lineLimit(1)
            }
            .multilineTextAlignment(.leading)
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .prefetchAlbumArtwork(url: item.coverURL)

        if let savedID = item.savedID {
            link.contextMenu {
                Button("从资料库移除", systemImage: "minus.circle", role: .destructive) { saved.remove(id: savedID) }
            }
        } else {
            link
        }
    }
}

/// 最近加入音乐文件夹的专辑与歌单，按文件加入时间从新到旧。
nonisolated private struct RecentLibraryItem: Identifiable, Sendable {
    enum Kind: Sendable { case album, playlist }
    let id: String
    let kind: Kind
    let title: String
    let subtitle: String
    let coverURL: URL?
    let addedAt: Date

    static let limit = 6

    @concurrent static func prepare(albums: [LocalAlbum], playlists: [LocalPlaylist]) async -> [Self] {
        let albumItems = albums.map { album in
            Self(id: album.id, kind: .album, title: album.title, subtitle: "\(album.artist) · \(album.entries.count) 首",
                 coverURL: album.coverURL, addedAt: album.entries.map { addedDate($0.fileURL) }.max() ?? .distantPast)
        }
        let playlistItems = playlists.map { playlist in
            Self(id: playlist.id, kind: .playlist, title: playlist.title, subtitle: "歌单 · \(playlist.tracks.count) 首",
                 coverURL: playlist.coverURL, addedAt: addedDate(playlist.fileURL))
        }
        return Array((albumItems + playlistItems).sorted { $0.addedAt > $1.addedAt }.prefix(limit))
    }

    /// 文件放进文件夹的时间；拿不到时用创建时间。
    private static func addedDate(_ url: URL) -> Date {
        let values = try? url.resourceValues(forKeys: [.addedToDirectoryDateKey, .creationDateKey])
        return values?.addedToDirectoryDate ?? values?.creationDate ?? .distantPast
    }

    @MainActor var collection: LibraryShelfItem {
        LibraryShelfItem(id: id, title: title, subtitle: subtitle, coverURL: coverURL, origin: .local,
                          route: kind == .album ? .localAlbum(id: id) : .localPlaylist(id: id), addedAt: addedAt)
    }
}

/// 在资料库的专辑、歌单与歌曲中按标题、歌手和专辑名查找。
private struct LibrarySearchResults: View {
    let query: String
    @Environment(OfflineLibraryStore.self) private var library
    @Environment(SavedLibraryStore.self) private var saved
    @Environment(PlayerStore.self) private var player

    var body: some View {
        let contents = LibraryContents(library: library, saved: saved)
        let collections = (contents.albums(.all) + contents.playlists(.all)).filter {
            $0.title.localizedStandardContains(query) || $0.subtitle.localizedStandardContains(query)
        }
        let songs = contents.songs(.all).filter {
            $0.track.title.localizedStandardContains(query) || $0.track.artists.localizedStandardContains(query)
                || $0.track.albumTitle.localizedStandardContains(query)
        }
        let shown = Array(songs.prefix(50))
        if collections.isEmpty && songs.isEmpty {
            ContentUnavailableView.search(text: query)
        }
        if !collections.isEmpty {
            Text("专辑与歌单").font(.title3.bold())
            ForEach(collections.prefix(6)) { item in
                NavigationLink(value: item.route) {
                    HStack(spacing: 12) {
                        ArtworkImage(url: item.coverURL, cornerRadius: 6).frame(width: 52, height: 52)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(item.title).foregroundStyle(DizzyPalette.text).lineLimit(1)
                            HStack(spacing: 6) {
                                LibraryOriginBadge(origin: item.origin)
                                Text(item.subtitle).font(.subheadline).foregroundStyle(DizzyPalette.mutedText).lineLimit(1)
                            }
                        }
                        Spacer()
                    }
                    .contentShape(.rect)
                }
                .buttonStyle(.plain)
            }
        }
        if !shown.isEmpty {
            Text("歌曲").font(.title3.bold())
            ForEach(Array(shown.enumerated()), id: \.element.id) { index, song in
                LibrarySongRow(song: song) { player.play(shown.map(\.track), startAt: index) }
            }
        }
    }
}

/// 一首资料库歌曲：封面、标题、来源 · 歌手 · 专辑；在线歌曲长按可从资料库移除。
struct LibrarySongRow: View {
    let song: LibrarySong
    var showsOrigin = true
    let play: () -> Void
    @Environment(PlayerStore.self) private var player
    @Environment(SavedLibraryStore.self) private var saved

    var body: some View {
        let track = song.track
        let row = Button(action: play) {
            HStack(spacing: 12) {
                ArtworkImage(url: track.coverURL, cornerRadius: 6).frame(width: 44, height: 44)
                VStack(alignment: .leading, spacing: 2) {
                    Text(track.title)
                        .foregroundStyle(player.currentTrack?.id == track.id ? DizzyPalette.accent : DizzyPalette.text)
                        .lineLimit(1)
                    HStack(spacing: 6) {
                        if showsOrigin { LibraryOriginBadge(origin: song.origin) }
                        Text([track.artists, track.albumTitle].filter { !$0.isEmpty }.joined(separator: " · "))
                            .font(.subheadline).foregroundStyle(DizzyPalette.mutedText).lineLimit(1)
                    }
                }
                Spacer(minLength: 0)
            }
            .frame(minHeight: 52)
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(track.title)，\(track.artists)")

        if let savedID = song.savedID {
            row.contextMenu {
                Button("从资料库移除", systemImage: "minus.circle", role: .destructive) { saved.remove(id: savedID) }
            }
        } else {
            row
        }
    }
}

/// 资料库歌曲列表；带歌手名时只列这位歌手的歌。
struct LibrarySongsPage: View {
    var artist: String?
    @State private var filter: LibraryOriginFilter
    @Environment(OfflineLibraryStore.self) private var library
    @Environment(SavedLibraryStore.self) private var saved
    @Environment(PlayerStore.self) private var player

    init(filter: LibraryOriginFilter, artist: String? = nil) {
        self.artist = artist
        _filter = State(initialValue: filter)
    }

    var body: some View {
        let all = LibraryContents(library: library, saved: saved).songs(filter)
        let songs = artist.map { name in all.filter { LibraryContents.artistNames($0.track).contains(name) } } ?? all
        let tracks = songs.map(\.track)
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 4) {
                LibraryOriginPicker(selection: $filter).padding(.bottom, 8)
                if songs.isEmpty {
                    ContentUnavailableView("没有歌曲", systemImage: "music.note",
                                           description: Text("换个来源看看，或在歌曲菜单里选「加入资料库」。"))
                } else {
                    AlbumPlaybackActions(isEmpty: false) { shuffled in
                        player.play(tracks, startAt: shuffled ? Int.random(in: tracks.indices) : 0)
                        if player.isShuffled != shuffled { player.toggleShuffle() }
                    }
                    .padding(.bottom, 12)
                    ForEach(Array(songs.enumerated()), id: \.element.id) { index, song in
                        LibrarySongRow(song: song, showsOrigin: filter == .all) { player.play(tracks, startAt: index) }
                    }
                }
            }
            .padding(.horizontal, 20).padding(.vertical, 8)
        }
        .dizzyPageBackground()
        .navigationTitle(artist ?? "歌曲")
        .navigationBarTitleDisplayMode(.large)
    }
}

/// 资料库里的歌手，点进去是这位歌手的歌曲。
struct LibraryArtistsPage: View {
    @State private var filter: LibraryOriginFilter
    @Environment(OfflineLibraryStore.self) private var library
    @Environment(SavedLibraryStore.self) private var saved

    init(filter: LibraryOriginFilter) { _filter = State(initialValue: filter) }

    var body: some View {
        let artists = LibraryContents.artists(in: LibraryContents(library: library, saved: saved).songs(filter))
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 0) {
                LibraryOriginPicker(selection: $filter).padding(.bottom, 8)
                if artists.isEmpty {
                    ContentUnavailableView("没有歌手", systemImage: "music.microphone")
                }
                ForEach(artists, id: \.name) { artist in
                    NavigationLink(value: AppRoute.libraryArtist(artist.name, filter: filter)) {
                        HStack(spacing: 12) {
                            Image(systemName: "person.crop.circle.fill")
                                .font(.system(size: 40))
                                .foregroundStyle(DizzyPalette.mutedText.opacity(0.5))
                                .accessibilityHidden(true)
                            Text(artist.name).foregroundStyle(DizzyPalette.text).lineLimit(1)
                            Spacer()
                            Text("\(artist.count) 首").font(.subheadline).foregroundStyle(DizzyPalette.mutedText)
                            Image(systemName: "chevron.right").font(.footnote.weight(.semibold)).foregroundStyle(.tertiary)
                        }
                        .frame(minHeight: 56)
                        .contentShape(.rect)
                    }
                    .buttonStyle(.plain)
                    Divider().padding(.leading, 52)
                }
            }
            .padding(.horizontal, 20).padding(.vertical, 8)
        }
        .dizzyPageBackground()
        .navigationTitle("歌手")
        .navigationBarTitleDisplayMode(.large)
    }
}

/// 本地歌单（可新建、删除）与加入资料库的在线歌单。
struct LocalPlaylistsPage: View {
    @State private var filter: LibraryOriginFilter
    @Environment(OfflineLibraryStore.self) private var library
    @Environment(SavedLibraryStore.self) private var saved

    init(filter: LibraryOriginFilter) { _filter = State(initialValue: filter) }

    var body: some View {
        let online = LibraryContents(library: library, saved: saved).online(.playlist, filter)
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                LibraryOriginPicker(selection: $filter)
                if filter.includes(.local) { LocalPlaylistsView() }
                if !online.isEmpty {
                    if filter.includes(.local) { SectionHeading(title: "在线歌单") }
                    LazyVGrid(columns: DizzyGrid.columns, alignment: .leading, spacing: 22) {
                        ForEach(online) { LibraryShelfCard(item: $0, showsOrigin: filter == .all) }
                    }
                } else if !filter.includes(.local) {
                    ContentUnavailableView("没有歌单", systemImage: "music.note.list",
                                           description: Text("在网易云歌单页点「加入资料库」。"))
                }
            }
            .padding(.horizontal, 20).padding(.vertical, 8)
        }
        .dizzyPageBackground()
        .navigationTitle("歌单")
        .navigationBarTitleDisplayMode(.large)
    }
}

/// 全部专辑：本地专辑长按可多选删除，在线专辑长按可从资料库移除。
struct LocalAlbumsPage: View {
    @State private var filter: LibraryOriginFilter
    @Environment(OfflineLibraryStore.self) private var library
    @Environment(SavedLibraryStore.self) private var saved
    @State private var selection = LocalAlbumSelection()
    @State private var items: [LocalLibraryAlbumItem] = []
    @State private var deletingAlbums: [LocalLibraryAlbumItem]?
    @State private var isDeleting = false
    @State private var deletionFailure: String?

    init(filter: LibraryOriginFilter) { _filter = State(initialValue: filter) }

    var body: some View {
        let local = filter.includes(.local) ? items : []
        let online = LibraryContents(library: library, saved: saved).online(.album, filter)
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 20) {
                LibraryOriginPicker(selection: $filter)
                if local.isEmpty && online.isEmpty && filter.includes(.local) && (library.isImporting || library.isScanning) {
                    ContentSkeleton(layout: .grid)
                } else if local.isEmpty && online.isEmpty {
                    ContentUnavailableView("没有专辑", systemImage: "square.stack",
                        description: Text("从「设置 › 音乐文件夹」导入音乐，或在专辑页点「加入资料库」。"))
                } else {
                    LazyVGrid(columns: DizzyGrid.columns, alignment: .leading, spacing: 22) {
                        ForEach(local) { album in
                            LocalLibraryAlbumCard(album: album, selection: selection, isDeleting: isDeleting,
                                                  showsOrigin: filter == .all) {
                                deletingAlbums = [album]
                            }
                        }
                        ForEach(online) { LibraryShelfCard(item: $0, showsOrigin: filter == .all) }
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
                LocalAlbumSelectionBar(selection: selection, ids: Set(local.map(\.id)), isDeleting: isDeleting) { ids in
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
        .onChange(of: filter) { _, _ in selection.finish() }
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
    var showsOrigin = false
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
                .overlay(alignment: .bottomLeading) {
                    if showsOrigin { LibraryOriginBadge(origin: .local, onArtwork: true).padding(7) }
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
                                       description: Text("专辑可能已被移动或删除，请下拉资料库重新扫描。"))
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
