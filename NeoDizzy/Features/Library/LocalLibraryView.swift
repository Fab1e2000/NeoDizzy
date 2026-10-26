import SwiftUI

/// 资料库首页固定汇总全部来源的歌曲、专辑和歌单。
struct LocalLibraryView: View {
    @Environment(OfflineLibraryStore.self) private var library
    @Environment(SavedLibraryStore.self) private var saved
    @Environment(ModuleRegistry.self) private var modules
    @Environment(AccountLibraryMirror.self) private var mirror
    @Environment(FavoritesStore.self) private var favorites
    @Environment(DownloadStore.self) private var downloads
    @Environment(PlaybackHistoryStore.self) private var history
    @State private var showsDownloads = false
    @State private var localRecent: [RecentLibraryItem] = []

    var body: some View {
        let recent = recentItems
        let played = history.availableSongs(library: library, modules: modules)
        List {
            Section {
                LibraryCategoryRows(recentlyPlayedCount: played.count)
            }
            .listSectionSeparator(.hidden)
            Section {
                if let issue = library.issue {
                    Label(issue, systemImage: "exclamationmark.triangle")
                        .font(.caption).foregroundStyle(DizzyPalette.accent)
                }
                if recent.isEmpty && played.isEmpty && (library.isImporting || library.isScanning) {
                    ContentSkeleton(layout: .grid)
                } else if recent.isEmpty && played.isEmpty {
                    ContentUnavailableView("资料库还是空的", systemImage: "music.note.list",
                        description: Text("导入音乐，或登录已启用的音乐平台：喜欢的歌、收藏的播放列表与专辑、已购专辑会出现在这里。"))
                } else if !recent.isEmpty {
                    RecentlyAddedGrid(items: recent)
                        .padding(.vertical, 16)
                }
            }
            .listSectionSeparator(.hidden)
            .listRowSeparator(.hidden)
            .listRowBackground(Color.clear)
            .listRowInsets(EdgeInsets(top: 8, leading: 20, bottom: 8, trailing: 20))
        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
        .dizzyPageBackground()
        .rootPageChrome(title: "资料库", action:
            PageHeaderAction(title: "下载队列", systemImage: "arrow.down.circle",
                             badge: downloads.jobs.filter(\.isActive).count) { showsDownloads = true })
        .refreshable {
            // 下拉刷新同步所有已注册平台。
            async let likes: Void = favorites.refresh()
            async let scan: Void = library.scan()
            async let sync: Void = mirror.refresh(force: true)
            _ = await (scan, sync, likes)
        }
        .sheet(isPresented: $showsDownloads) { DownloadQueueSheet() }
        .task(id: library.contentRevision) {
            let result = await RecentLibraryItem.prepare(albums: library.visibleAlbums, playlists: library.localPlaylists)
            guard !Task.isCancelled else { return }
            localRecent = result
        }
    }

    private var recentItems: [LibraryShelfItem] {
        let contents = LibraryContents(library: library, saved: saved, mirror: mirror, favorites: favorites, modules: modules)
        let albums = contents.onlineAlbumsByKey
        let local = localRecent.map { item in
            item.kind == .album
                ? contents.localAlbumItem(id: item.id, title: item.title, subtitle: item.subtitle, coverURL: item.coverURL,
                                          addedAt: item.addedAt, online: albums)
                : item.collection
        }
        let online = contents.recentOnline(.all)
        return Array((local + online).sorted { $0.addedAt > $1.addedAt }.prefix(RecentLibraryItem.limit))
    }

}

/// 最近添加只在首页展示最新十项，固定两列、最多五行。
private struct RecentlyAddedGrid: View {
    let items: [LibraryShelfItem]
    private let columns = [GridItem(.flexible(), spacing: 14), GridItem(.flexible(), spacing: 14)]

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("最近添加").font(.title2.bold()).accessibilityAddTraits(.isHeader)
            LazyVGrid(columns: columns, alignment: .leading, spacing: 22) {
                ForEach(items.prefix(10)) { item in
                    LibraryShelfCard(item: item, showsOrigin: true)
                }
            }
        }
    }
}

/// 从分类列表进入，按实际播放顺序展示歌曲。
private struct RecentlyPlayedPage: View {
    @Environment(PlaybackHistoryStore.self) private var history
    @Environment(OfflineLibraryStore.self) private var library
    @Environment(ModuleRegistry.self) private var modules
    @Environment(PlayerStore.self) private var player

    var body: some View {
        let songs = history.availableSongs(library: library, modules: modules)
        let tracks = songs.map(\.track)
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 0) {
                if songs.isEmpty {
                    ContentUnavailableView("暂无最近播放", systemImage: "clock",
                                           description: Text("播放过的歌曲会显示在这里。"))
                } else {
                    AlbumPlaybackActions(isEmpty: false) { shuffled in
                        player.play(tracks, startAt: shuffled ? Int.random(in: tracks.indices) : 0)
                        if player.isShuffled != shuffled { player.toggleShuffle() }
                    }
                    .padding(.bottom, 12)
                    ForEach(songs.enumerated(), id: \.element.id) { index, song in
                        LibrarySongRow(song: song) { player.play(tracks, startAt: index) }
                    }
                }
            }
            .padding(.horizontal, 20).padding(.vertical, 8)
        }
        .dizzyPageBackground()
        .navigationTitle("最近播放")
        .navigationBarTitleDisplayMode(.large)
    }
}

private extension PlaybackHistoryStore {
    func availableSongs(library: OfflineLibraryStore, modules: ModuleRegistry) -> [LibrarySong] {
        songs.compactMap { entry in
            let track = entry.track
            if track.localSource != nil {
                guard library.localFile(for: track) != nil else { return nil }
                return LibrarySong(track: track, origin: .local)
            }
            guard let provider = track.playbackProviderID,
                  let origin = modules.origin(providerID: provider) else { return nil }
            return LibrarySong(track: track, origin: origin)
        }
    }
}

/// 资料库首页的分类列表：与「音乐」App 资料库相同，一行一类，图标用主题色，数量计入全部来源。
private struct LibraryCategoryRows: View {
    let recentlyPlayedCount: Int
    @Environment(OfflineLibraryStore.self) private var library
    @Environment(SavedLibraryStore.self) private var saved
    @Environment(ModuleRegistry.self) private var modules
    @Environment(AccountLibraryMirror.self) private var mirror
    @Environment(FavoritesStore.self) private var favorites
    @ScaledMetric(relativeTo: .title3) private var iconWidth = 28.0

    private struct Row: Identifiable {
        let title: LocalizedStringKey
        let systemImage: String
        let count: Int
        let route: AppRoute
        var id: String { systemImage }
    }

    var body: some View {
        let contents = LibraryContents(library: library, saved: saved, mirror: mirror, favorites: favorites, modules: modules)
        let songs = contents.songs(.all)
        let rows = [
            Row(title: "播放列表", systemImage: "music.note.list", count: contents.playlists(.all).count + 1, route: .libraryPlaylists(.all)),
            Row(title: "专辑", systemImage: "square.stack", count: contents.albums(.all).count, route: .libraryAlbums(.all)),
            Row(title: "歌曲", systemImage: "music.note", count: songs.count, route: .librarySongs(.all)),
            Row(title: "歌手", systemImage: "music.microphone", count: LibraryContents.artists(in: songs).count,
                route: .libraryArtists(.all)),
            Row(title: "最近播放", systemImage: "clock", count: recentlyPlayedCount,
                route: .page { RecentlyPlayedPage() }),
        ]
        ForEach(rows) { row in
            NavigationLink(value: row.route) {
                HStack(spacing: 14) {
                    Image(systemName: row.systemImage)
                        .font(.title3)
                        .foregroundStyle(DizzyPalette.accent)
                        .frame(width: iconWidth)
                        .accessibilityHidden(true)
                    Text(row.title).font(.title3).foregroundStyle(DizzyPalette.text)
                    Spacer(minLength: 8)
                    Text("\(row.count)").font(.body).monospacedDigit().foregroundStyle(DizzyPalette.mutedText)
                }
                .frame(minHeight: 44)
            }
            .listRowSeparator(.hidden)
            .listRowInsets(EdgeInsets(top: 4, leading: 20, bottom: 4, trailing: 20))
            .listRowBackground(Color.clear)
        }
    }
}

/// 从资料库移除一项会做什么：只删 App 里的记录，或同时取消网易云账号里的喜欢、收藏。
enum LibraryRemoval: Equatable {
    case saved(String)
    case account(providerID: String, kind: String, itemID: String, notice: String)
    var accountNotice: String? {
        if case .account(_, _, _, let notice) = self { return notice }
        return nil
    }
}

/// 一首资料库歌曲：本地文件、账号喜欢或手动保存的在线歌曲。
struct LibrarySong: Identifiable {
    let track: Track
    let origin: LibraryOrigin
    var removal: LibraryRemoval?
    var id: String { track.id }
}

/// 一张专辑或一个歌单：本地的、账号同步来的，或手动加入的。
struct LibraryShelfItem: Identifiable {
    let id: String
    let title: String
    let subtitle: String
    let coverURL: URL?
    let origin: LibraryOrigin
    let route: AppRoute
    var addedAt: Date
    var removal: LibraryRemoval?
    /// 在线条目的「平台/ID」，用来和下载来的本地专辑对上。
    var sourceKey: String?
    /// 下载来的专辑在本地库里的 ID；有值时长按可删除下载。
    var downloadedAlbumID: String?
    var isWholeAlbumDownload = false
    /// 在 `CollectionTrackIndex` 里查完整曲目列表用的键。
    var trackKey: String?

    /// 下载来的专辑在「本地」筛选下也显示。
    func isShown(in filter: LibraryOriginFilter) -> Bool {
        filter.includes(origin) || (downloadedAlbumID != nil && filter.includes(.local))
    }

    init(id: String, title: String, subtitle: String, coverURL: URL?, origin: LibraryOrigin, route: AppRoute,
         addedAt: Date, removal: LibraryRemoval? = nil) {
        self.id = id; self.title = title; self.subtitle = subtitle; self.coverURL = coverURL
        self.origin = origin; self.route = route; self.addedAt = addedAt; self.removal = removal
    }

    init?(saved item: SavedLibraryItem, modules: ModuleRegistry) {
        guard let origin = modules.origin(providerID: item.providerID),
              let route = modules.collectionRoute(providerID: item.providerID, kind: item.kind.rawValue, itemID: item.itemID) else { return nil }
        self.init(id: item.id, title: item.title, subtitle: item.subtitle, coverURL: item.coverURL,
                  origin: origin, route: route, addedAt: item.addedAt, removal: .saved(item.id))
        sourceKey = "\(item.providerID)/\(item.itemID)"
        trackKey = CollectionTrackIndex.key(provider: item.providerID, kind: item.kind.rawValue, id: item.itemID)
    }
    init?(mirrored item: MirroredCollection, modules: ModuleRegistry) {
        guard let origin = modules.origin(providerID: item.providerID),
              let route = modules.collectionRoute(providerID: item.providerID, kind: item.kind.rawValue, itemID: item.itemID) else { return nil }
        self.init(id: item.id, title: item.title, subtitle: item.subtitle, coverURL: item.coverURL,
                  origin: origin, route: route, addedAt: item.firstSeen, removal: modules.collectionRemoval(for: item))
        sourceKey = "\(item.providerID)/\(item.itemID)"
        trackKey = CollectionTrackIndex.key(provider: item.providerID, kind: item.kind.rawValue, id: item.itemID)
    }

}

/// 把本地库、账号镜像和手动加入的条目合成一份内容，按来源筛选。
@MainActor
struct LibraryContents {
    let library: OfflineLibraryStore
    let saved: SavedLibraryStore
    let mirror: AccountLibraryMirror
    var favorites: FavoritesStore? = nil
    let modules: ModuleRegistry

    func songs(_ filter: LibraryOriginFilter) -> [LibrarySong] {
        var songs: [LibrarySong] = []
        if filter.includes(.local) {
            songs += library.visibleAlbums.flatMap(\.tracks).map { LibrarySong(track: $0, origin: .local) }
        }
        let existing = Set(songs.map(\.id))
        songs += (favorites?.songs ?? []).compactMap { song in
            guard let origin = modules.origin(providerID: song.providerID), filter.includes(origin),
                  !existing.contains(song.track.id) else { return nil }
            return LibrarySong(track: song.track, origin: origin)
        }
        songs += saved.items(of: .song)
            .compactMap { item in
                guard let origin = modules.origin(providerID: item.providerID), filter.includes(origin),
                      let track = item.track, !songs.contains(where: { $0.id == track.id }) else { return nil }
                return LibrarySong(track: track, origin: origin, removal: .saved(item.id))
            }
        return songs.sorted { $0.track.title.localizedStandardCompare($1.track.title) == .orderedAscending }
    }

    func albums(_ filter: LibraryOriginFilter) -> [LibraryShelfItem] {
        let online = onlineAlbumsByKey
        let local = library.visibleAlbums.map { album in
            localAlbumItem(id: album.id, title: album.title, subtitle: album.artist, coverURL: album.coverURL,
                           addedAt: .distantPast, online: online)
        }.filter { $0.isShown(in: filter) }
        return local + self.online(.album, filter)
    }

    /// 本地专辑的卡片，点开总是进本地专辑页。下载来的专辑显示在线来源，
    /// 资料库里同一张在线专辑并进这张卡片，带上它的移除操作。
    func localAlbumItem(id: String, title: String, subtitle: String, coverURL: URL?, addedAt: Date,
                        online: [String: LibraryShelfItem]) -> LibraryShelfItem {
        guard let source = library.albumSources[id], let origin = modules.origin(providerID: source.provider) ?? LibraryOrigin(providerID: source.provider), origin != .local else {
            return LibraryShelfItem(id: id, title: title, subtitle: subtitle, coverURL: coverURL,
                                    origin: .local, route: .localAlbum(id: id), addedAt: addedAt)
        }
        let key = "\(source.provider)/\(source.id)"
        var item = LibraryShelfItem(id: id, title: title, subtitle: subtitle, coverURL: coverURL, origin: origin,
                                    route: .localAlbum(id: id), addedAt: addedAt, removal: online[key]?.removal)
        item.sourceKey = key
        item.trackKey = CollectionTrackIndex.key(provider: source.provider, kind: "album", id: source.id)
        item.downloadedAlbumID = id
        item.isWholeAlbumDownload = modules.downloadsWholeAlbums(providerID: source.provider)
        return item
    }

    /// 资料库里的在线专辑（含已下载的），按「平台/ID」查。
    var onlineAlbumsByKey: [String: LibraryShelfItem] {
        Dictionary(online(.album, .all, includingDownloaded: true).compactMap { item in item.sourceKey.map { ($0, item) } },
                   uniquingKeysWith: { first, _ in first })
    }

    func playlists(_ filter: LibraryOriginFilter) -> [LibraryShelfItem] {
        let local = filter.includes(.local) ? library.localPlaylists.map { playlist in
            LibraryShelfItem(id: playlist.id, title: playlist.title, subtitle: "\(playlist.tracks.count) 首", coverURL: playlist.coverURL,
                              origin: .local, route: .localPlaylist(id: playlist.id), addedAt: .distantPast)
        } : []
        return local + online(.playlist, filter)
    }

    /// 在线专辑或歌单。网易云歌单保持账号里的顺序（「我喜欢的音乐」在最前），其余按名称。
    /// 已下载的在线专辑由本地那张卡片代表，默认不再单独列出。
    func online(_ kind: MirroredCollection.Kind, _ filter: LibraryOriginFilter,
                includingDownloaded: Bool = false) -> [LibraryShelfItem] {
        let mirrored = mirror.collections.filter { $0.kind == kind && !$0.isLikedPlaylist }
            .compactMap { LibraryShelfItem(mirrored: $0, modules: modules) }
        let known = Set(mirror.collections.map { "\($0.providerID)/\($0.kind.rawValue)/\($0.itemID)" })
        let manual = saved.items.filter { $0.kind.rawValue == kind.rawValue && !known.contains("\($0.providerID)/\($0.kind.rawValue)/\($0.itemID)") }
            .compactMap { LibraryShelfItem(saved: $0, modules: modules) }
        let downloaded = kind == .album && !includingDownloaded
            ? Set(library.albumSources.values.map { "\($0.provider)/\($0.id)" }) : []
        let items = (mirrored + manual).filter { filter.includes($0.origin) && !downloaded.contains($0.sourceKey ?? "") }
        return kind == .playlist ? items
            : items.sorted { $0.title.localizedStandardCompare($1.title) == .orderedAscending }
    }

    /// 最近同步进来或手动加入的在线专辑与歌单。
    func recentOnline(_ filter: LibraryOriginFilter) -> [LibraryShelfItem] {
        (online(.album, filter) + online(.playlist, filter))
    }

    /// 歌手、歌曲数和第一首歌的封面（没有网易云头像时用），按名称排序。
    static func artists(in songs: [LibrarySong]) -> [LibraryArtist] {
        var artists: [String: LibraryArtist] = [:]
        for song in songs {
            for name in artistNames(song.track) {
                artists[name, default: LibraryArtist(name: name, count: 0, coverURL: song.track.coverURL)].count += 1
                if artists[name]?.coverURL == nil { artists[name]?.coverURL = song.track.coverURL }
            }
        }
        return artists.values.sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }

    static func artistNames(_ track: Track) -> [String] {
        let names = LibraryArtistNames.split(track.artists)
        return names.isEmpty ? [String(localized: "未知歌手")] : names
    }
}

struct LibraryArtist {
    let name: String
    var count: Int
    var coverURL: URL?
}

/// 歌手头像：网易云歌手用平台头像，其余用这位歌手第一首歌的封面。
private struct LibraryArtistAvatar: View {
    let artist: LibraryArtist
    @Environment(LibraryProviderRegistry.self) private var providers
    var body: some View {
        ArtworkImage(url: providers.artistAvatar(named: artist.name) ?? artist.coverURL, cornerRadius: 0)
            .frame(width: 44, height: 44)
            .clipShape(.circle)
            .accessibilityHidden(true)
            .task(id: providers.artistLookupKey(named: artist.name)) { await providers.loadArtistAvatar(named: artist.name) }
    }
}

/// 歌曲和搜索结果副标题前的来源标记。
struct LibraryOriginBadge: View {
    let origin: LibraryOrigin
    @Environment(ModuleRegistry.self) private var modules: ModuleRegistry?
    private var label: String { modules?.origin(providerID: origin.rawValue)?.label ?? origin.label }

    var body: some View {
        Text(label)
            .font(.caption2.weight(.semibold))
            .foregroundStyle(DizzyPalette.mutedText)
            .padding(.horizontal, 5)
            .padding(.vertical, 1)
            .background {
                RoundedRectangle(cornerRadius: 4).strokeBorder(DizzyPalette.mutedText.opacity(0.6), lineWidth: 1)
            }
            .accessibilityLabel("来源：\(label)")
    }
}

/// 封面右下角的标记：来源图标，下载过的再加「已下载」图标，放在同一个胶囊里。
struct LibraryOriginMark: View {
    @Environment(ModuleRegistry.self) private var modules: ModuleRegistry?
    var origin: LibraryOrigin?
    var state: CollectionOfflineState?

    var body: some View {
        HStack(spacing: 5) {
            if let origin { Image(systemName: modules?.origin(providerID: origin.rawValue)?.systemImage ?? origin.systemImage) }
            if let state { Image(systemName: state == .downloaded ? "arrow.down.circle.fill" : "arrow.down.circle") }
        }
        .font(.system(size: 12, weight: .semibold))
        .foregroundStyle(.primary)
        .padding(.horizontal, 6)
        .frame(minWidth: 24, minHeight: 24)
        .background(.ultraThinMaterial, in: Capsule())
        .overlay { Capsule().strokeBorder(.primary.opacity(0.08), lineWidth: 0.5) }
        .padding(6)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityText)
    }

    private var accessibilityText: String {
        let status = state.map { $0 == .downloaded ? String(localized: "已下载") : String(localized: "已缓存") }
        return [origin.map { String(localized: "来源：\(modules?.origin(providerID: $0.rawValue)?.label ?? $0.label)") }, status].compactMap(\.self).joined(separator: "，")
    }
}

extension View {
    /// 在封面右下角叠来源和离线状态：全部下载是实心箭头，全部下载或缓存是空心箭头。
    /// 曲目列表未知时（在线专辑、歌单没打开过）只显示来源；`downloaded` 用于整张下载的专辑。
    func libraryOriginMark(_ origin: LibraryOrigin?, tracks: [Track]? = nil, downloaded: Bool = false) -> some View {
        overlay(alignment: .bottomTrailing) { CollectionOfflineMark(origin: origin, tracks: tracks, downloaded: downloaded) }
    }

    func libraryOriginMark(_ origin: LibraryOrigin?, item: LibraryShelfItem) -> some View {
        libraryOriginMark(origin, tracks: item.trackKey.flatMap(CollectionTrackIndex.shared.tracks(for:)),
                          downloaded: item.downloadedAlbumID != nil && item.isWholeAlbumDownload)
    }
}

private struct CollectionOfflineMark: View {
    let origin: LibraryOrigin?
    let tracks: [Track]?
    let downloaded: Bool
    @Environment(PlayerStore.self) private var player
    @Environment(OfflineLibraryStore.self) private var library

    var body: some View {
        // 没有完整曲目索引时，已入库的下载专辑仍可标为已下载。
        let state = tracks.flatMap { CollectionOfflineState.resolve($0, isDownloaded: library.hasLocalFile(for:),
                                                                    isCached: { player.cachedQuality(for: $0) != nil }) }
            ?? (downloaded ? .downloaded : nil)
        if origin != nil || state != nil { LibraryOriginMark(origin: origin, state: state) }
    }
}

/// 专辑或歌单卡片；在线条目长按可从资料库移除。
struct LibraryShelfCard: View {
    let item: LibraryShelfItem
    var showsOrigin = true
    @Environment(SavedLibraryStore.self) private var saved
    @Environment(ModuleRegistry.self) private var modules
    @Environment(AccountLibraryMirror.self) private var mirror
    @Environment(FavoritesStore.self) private var favorites

    var body: some View {
        let link = AlbumNavigationLink(value: item.route, artworkURL: item.coverURL) {
            VStack(alignment: .leading, spacing: 6) {
                ArtworkImage(url: item.coverURL)
                    .libraryOriginMark(showsOrigin ? item.origin : nil, item: item)
                Text(item.title).font(.subheadline.weight(.semibold)).foregroundStyle(DizzyPalette.text).lineLimit(1)
                Text(item.subtitle).font(.caption).foregroundStyle(DizzyPalette.mutedText).lineLimit(1)
            }
            .multilineTextAlignment(.leading)
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .prefetchAlbumArtwork(url: item.coverURL)

        link.libraryRemoval(item.removal, title: item.title, downloadedAlbumID: item.downloadedAlbumID)
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

    static let limit = 60

    @concurrent static func prepare(albums: [LocalAlbum], playlists: [LocalPlaylist]) async -> [Self] {
        let albumItems = albums.map { album in
            Self(id: album.id, kind: .album, title: album.title, subtitle: "\(album.artist) · \(album.entries.count) 首",
                 coverURL: album.coverURL, addedAt: album.entries.map { addedDate($0.fileURL) }.max() ?? .distantPast)
        }
        let playlistItems = playlists.map { playlist in
            Self(id: playlist.id, kind: .playlist, title: playlist.title, subtitle: "播放列表 · \(playlist.tracks.count) 首",
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
extension LibraryContents {
    func search(_ query: String) -> (collections: [LibraryShelfItem], songs: [LibrarySong]) {
        let collections = (albums(.all) + playlists(.all)).filter {
            $0.title.localizedStandardContains(query) || $0.subtitle.localizedStandardContains(query)
        }
        let songs = songs(.all).filter {
            $0.track.title.localizedStandardContains(query) || $0.track.artists.localizedStandardContains(query)
                || $0.track.albumTitle.localizedStandardContains(query)
        }
        return (collections, songs)
    }
}

/// 统一搜索里的「资料库」一组：前两个专辑或歌单、前三首歌。
struct LibrarySearchSection: View {
    let query: String
    @Environment(OfflineLibraryStore.self) private var library
    @Environment(SavedLibraryStore.self) private var saved
    @Environment(ModuleRegistry.self) private var modules
    @Environment(AccountLibraryMirror.self) private var mirror
    @Environment(FavoritesStore.self) private var favorites
    @Environment(PlayerStore.self) private var player

    var body: some View {
        let result = LibraryContents(library: library, saved: saved, mirror: mirror, favorites: favorites, modules: modules).search(query)
        let collections = Array(result.collections.prefix(2))
        let songs = Array(result.songs.prefix(3))
        if result.collections.isEmpty && result.songs.isEmpty {
            SearchGroup(title: String(localized: "资料库")) {
                SearchCardRow { SearchSectionMessage(text: String(localized: "资料库里没有和「\(query)」相关的内容。")) }
            }
        } else {
            SearchGroup(title: String(localized: "资料库"),
                        allResults: result.collections.count > collections.count || result.songs.count > songs.count
                            ? .librarySearch(query) : nil) {
                ForEach(collections) { item in
                    AlbumNavigationLink(value: item.route, artworkURL: item.coverURL) {
                        SearchMediaRow(title: item.title, subtitle: "\(item.origin.label) · \(item.subtitle)", artworkURL: item.coverURL)
                    }
                    .buttonStyle(.plain)
                }
                ForEach(Array(songs.enumerated()), id: \.element.id) { index, song in
                    SongRow(track: song.track, isDownloaded: song.origin == .local) {
                        player.play(result.songs.map(\.track), startAt: index)
                    }
                }
            }
        }
    }
}

/// 「查看全部」：资料库里的全部匹配结果，与 MeloX 的搜索结果一样用普通列表。
struct LibrarySearchPage: View {
    let query: String
    @Environment(OfflineLibraryStore.self) private var library
    @Environment(SavedLibraryStore.self) private var saved
    @Environment(ModuleRegistry.self) private var modules
    @Environment(AccountLibraryMirror.self) private var mirror
    @Environment(FavoritesStore.self) private var favorites
    @Environment(PlayerStore.self) private var player

    var body: some View {
        let result = LibraryContents(library: library, saved: saved, mirror: mirror, favorites: favorites, modules: modules).search(query)
        let songs = Array(result.songs.prefix(200))
        List {
            if !result.collections.isEmpty {
                Section("专辑与播放列表") {
                    ForEach(result.collections) { item in
                        AlbumNavigationLink(value: item.route, artworkURL: item.coverURL) {
                            SearchMediaRow(title: item.title, subtitle: "\(item.origin.label) · \(item.subtitle)", artworkURL: item.coverURL,
                                           showsChevron: false)
                        }
                        .songListRow()
                    }
                }
                .listRowSeparator(.hidden)
                .listSectionSeparator(.hidden)
            }
            if !songs.isEmpty {
                Section("歌曲") {
                    ForEach(Array(songs.enumerated()), id: \.element.id) { index, song in
                        SongRow(track: song.track, isDownloaded: song.origin == .local) {
                            player.play(songs.map(\.track), startAt: index)
                        }
                        .songListRow()
                    }
                }
                .listRowSeparator(.hidden)
                .listSectionSeparator(.hidden)
            }
        }
        .listStyle(.plain)
        .overlay {
            if result.collections.isEmpty && result.songs.isEmpty { ContentUnavailableView.search(text: query) }
        }
        .navigationTitle("资料库 · 「\(query)」")
        .navigationBarTitleDisplayMode(.inline)
    }
}

/// 一首资料库歌曲：封面式歌曲行，加来源标记；在线歌曲的菜单里可从资料库移除。
struct LibrarySongRow: View {
    let song: LibrarySong
    var showsOrigin = true
    let play: () -> Void
    @Environment(SavedLibraryStore.self) private var saved

    var body: some View {
        SongRow(track: song.track, origin: showsOrigin ? song.origin : nil,
                actions: removal, play: play)
    }

    private var removal: [SongRowAction] {
        guard case .saved(let id) = song.removal else { return [] }
        return [.init(id: "remove", title: "从资料库移除", systemImage: "rectangle.stack.badge.minus", role: .destructive) { saved.remove(id: id) }]
    }
}

/// 资料库歌曲列表；带歌手名时只列这位歌手的歌。
struct LibrarySongsPage: View {
    var artist: String?
    let filter: LibraryOriginFilter
    @Environment(OfflineLibraryStore.self) private var library
    @Environment(SavedLibraryStore.self) private var saved
    @Environment(ModuleRegistry.self) private var modules
    @Environment(AccountLibraryMirror.self) private var mirror
    @Environment(FavoritesStore.self) private var favorites
    @Environment(PlayerStore.self) private var player

    init(filter: LibraryOriginFilter, artist: String? = nil) {
        self.artist = artist
        self.filter = filter
    }

    var body: some View {
        let all = LibraryContents(library: library, saved: saved, mirror: mirror, favorites: favorites, modules: modules).songs(filter)
        let songs = artist.map { name in all.filter { LibraryContents.artistNames($0.track).contains(name) } } ?? all
        let tracks = songs.map(\.track)
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 0) {
                if songs.isEmpty {
                    ContentUnavailableView("没有歌曲", systemImage: "music.note",
                                           description: Text("换个来源看看，或在歌曲菜单里选「喜欢」。"))
                } else {
                    AlbumPlaybackActions(isEmpty: false) { shuffled in
                        player.play(tracks, startAt: shuffled ? Int.random(in: tracks.indices) : 0)
                        if player.isShuffled != shuffled { player.toggleShuffle() }
                    }
                    .padding(.bottom, 12)
                    ForEach(Array(songs.enumerated()), id: \.element.id) { index, song in
                        LibrarySongRow(song: song, showsOrigin: filter == .all) {
                            player.play(tracks, startAt: index)
                        }
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
    let filter: LibraryOriginFilter
    @Environment(OfflineLibraryStore.self) private var library
    @Environment(SavedLibraryStore.self) private var saved
    @Environment(ModuleRegistry.self) private var modules
    @Environment(AccountLibraryMirror.self) private var mirror
    @Environment(FavoritesStore.self) private var favorites

    init(filter: LibraryOriginFilter) { self.filter = filter }

    var body: some View {
        let artists = LibraryContents.artists(in: LibraryContents(library: library, saved: saved, mirror: mirror, favorites: favorites, modules: modules).songs(filter))
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 0) {
                if artists.isEmpty {
                    ContentUnavailableView("没有歌手", systemImage: "music.microphone")
                }
                ForEach(artists, id: \.name) { artist in
                    NavigationLink(value: AppRoute.libraryArtist(artist.name, filter: filter)) {
                        HStack(spacing: 12) {
                            LibraryArtistAvatar(artist: artist)
                            Text(artist.name).foregroundStyle(DizzyPalette.text).lineLimit(1)
                            Spacer()
                            Text("\(artist.count) 首").font(.subheadline).foregroundStyle(DizzyPalette.mutedText)
                            Image(systemName: "chevron.right").font(.footnote.weight(.semibold)).foregroundStyle(.tertiary)
                        }
                        .frame(minHeight: 56)
                        .contentShape(.rect)
                    }
                    .buttonStyle(.plain)
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
    let filter: LibraryOriginFilter
    @Environment(OfflineLibraryStore.self) private var library
    @Environment(SavedLibraryStore.self) private var saved
    @Environment(ModuleRegistry.self) private var modules
    @Environment(AccountLibraryMirror.self) private var mirror
    @Environment(FavoritesStore.self) private var favorites

    init(filter: LibraryOriginFilter) { self.filter = filter }

    var body: some View {
        let online = LibraryContents(library: library, saved: saved, mirror: mirror, favorites: favorites, modules: modules).online(.playlist, filter)
        ScrollView {
            LocalPlaylistsView(online: online, showsLocal: filter.includes(.local), showsOrigin: filter == .all, showsFavorites: filter == .all)
            .padding(.horizontal, 20).padding(.vertical, 8)
        }
        .dizzyPageBackground()
        .navigationTitle("播放列表")
        .navigationBarTitleDisplayMode(.large)
    }
}

/// 全部专辑：本地专辑长按可多选删除，在线专辑长按可从资料库移除。
struct LocalAlbumsPage: View {
    @Environment(\.setMiniPlayerSuppressed) private var setMiniPlayerSuppressed
    let filter: LibraryOriginFilter
    @Environment(OfflineLibraryStore.self) private var library
    @Environment(SavedLibraryStore.self) private var saved
    @Environment(ModuleRegistry.self) private var modules
    @Environment(AccountLibraryMirror.self) private var mirror
    @Environment(FavoritesStore.self) private var favorites
    @State private var selection = LocalAlbumSelection()
    @State private var items: [LocalLibraryAlbumItem] = []
    @State private var deletingAlbums: [LocalLibraryAlbumItem]?
    @State private var isDeleting = false
    @State private var deletionFailure: String?

    init(filter: LibraryOriginFilter) { self.filter = filter }

    var body: some View {
        let contents = LibraryContents(library: library, saved: saved, mirror: mirror, favorites: favorites, modules: modules)
        let albums = contents.onlineAlbumsByKey
        let local = items.map { album in
            LocalAlbumCardItem(album: album, shelf: contents.localAlbumItem(
                id: album.id, title: album.title, subtitle: album.artist, coverURL: album.coverURL,
                addedAt: .distantPast, online: albums))
        }.filter { $0.shelf.isShown(in: filter) }
        let online = contents.online(.album, filter)
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 20) {
                if local.isEmpty && online.isEmpty && filter.includes(.local) && (library.isImporting || library.isScanning) {
                    ContentSkeleton(layout: .grid)
                } else if local.isEmpty && online.isEmpty {
                    ContentUnavailableView("没有专辑", systemImage: "square.stack",
                        description: Text("把音乐放进「文件 › 我的 iPhone › NeoDizzy」，或在专辑页点「加入资料库」。"))
                } else {
                    LazyVGrid(columns: DizzyGrid.columns, alignment: .leading, spacing: 22) {
                        ForEach(local) { card in
                            LocalLibraryAlbumCard(album: card.album, shelf: card.shelf, selection: selection,
                                                  isDeleting: isDeleting, showsOrigin: filter == .all) {
                                deletingAlbums = [card.album]
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
        // 与 MeloX 相同：多选时收起迷你播放器，给底部操作栏让位；离开页面时恢复。
        .onChange(of: selection.isSelecting, initial: true) { _, selecting in setMiniPlayerSuppressed(selecting) }
        .onDisappear { setMiniPlayerSuppressed(false) }
        .confirmationDialog("删除专辑？", item: $deletingAlbums, titleVisibility: .visible) { albums in
            Button("删除", role: .destructive) { delete(albums) }
            Button("取消", role: .cancel) { }
        } message: { albums in
            Text("\(albums.count) 张专辑，\(albums.reduce(0) { $0 + $1.count }) 首")
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

/// 专辑页里的一张本地专辑，带上它在资料库里的卡片信息（来源、点开去哪、移除操作）。
private struct LocalAlbumCardItem: Identifiable {
    let album: LocalLibraryAlbumItem
    let shelf: LibraryShelfItem
    var id: String { album.id }
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
                    .tint(DizzyPalette.accentFill)
                    .foregroundStyle(DizzyPalette.onAccent)
                    .controlSize(.large)
                    .disabled(isDeleting)
            }
        }
    }
}

private struct LocalLibraryAlbumCard: View {
    let album: LocalLibraryAlbumItem
    let shelf: LibraryShelfItem
    let selection: LocalAlbumSelection
    let isDeleting: Bool
    var showsOrigin = false
    let delete: () -> Void
    @Environment(\.openRoute) private var openRoute
    @Environment(\.albumNavigationNamespace) private var transitionNamespace
    @State private var confirmingRemoval = false
    @State private var navigationPreparation = AlbumNavigationPreparation()
    @State private var transitionID = UUID()
    private var isSelected: Bool { selection.ids.contains(album.id) }
    private var isDownloaded: Bool { shelf.downloadedAlbumID != nil }

    private var transitionSource: AlbumNavigationSource? {
        guard let transitionNamespace, let artworkURL = album.coverURL else { return nil }
        return AlbumNavigationSource(id: transitionID, namespace: transitionNamespace, artworkURL: artworkURL)
    }

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
                        Button(isDownloaded ? "删除下载" : "删除", systemImage: "trash", role: .destructive, action: delete)
                            .disabled(isDeleting)
                        if shelf.removal != nil {
                            Button("取消收藏", systemImage: "rectangle.stack.badge.minus", role: .destructive) {
                                confirmingRemoval = true
                            }
                        }
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
        .task(id: navigationPreparation.request) {
            guard let pending = navigationPreparation.request else { return }
            if let route = await navigationPreparation.finish(pending), !selection.isSelecting,
               shelf.route == pending.route, album.coverURL == pending.artworkURL {
                navigate(to: route)
            }
        }
        .onChange(of: selection.isSelecting) { navigationPreparation.cancel() }
        .onChange(of: album.id) { navigationPreparation.cancel() }
        .onChange(of: album.coverURL) { navigationPreparation.cancel() }
        .onDisappear { navigationPreparation.cancel() }
        .libraryRemovalConfirmation(shelf.removal, title: album.title, isPresented: $confirmingRemoval)
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
                .libraryOriginMark(showsOrigin ? shelf.origin : nil, item: shelf)
                .overlay(alignment: .topTrailing) {
                    if selection.isSelecting {
                        Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                            .font(.title3.weight(.semibold))
                            .foregroundStyle(isSelected ? DizzyPalette.accent : .white)
                            .background(.black.opacity(0.35), in: Circle())
                            .padding(8)
                    }
                }
                .environment(\.albumNavigationSource, transitionSource)

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
        } else if let route = navigationPreparation.begin(shelf.route, artworkURL: album.coverURL) {
            navigate(to: route)
        }
    }

    private func navigate(to route: AppRoute) {
        openRoute(transitionSource.map { route.zooming(from: $0.id) } ?? route)
    }
}

struct LocalAlbumDetailView: View {
    let id: String
    @State private var editing: AudioTagEditTarget?
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
                            SongRow(track: entry.track, style: .numbered(entry.track.number), editTags: {
                                editing = AudioTagEditTarget(track: entry.track, url: entry.fileURL)
                            }) {
                                if let index = album.tracks.firstIndex(where: { $0.id == entry.track.id }) {
                                    player.play(album.tracks, startAt: index)
                                }
                            }
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
