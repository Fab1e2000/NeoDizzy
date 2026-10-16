import SwiftUI

struct NeteaseHomeView: View {
    @Environment(PlayerStore.self) private var player
    @Environment(NowPlayingPresentation.self) private var nowPlaying
    @Environment(NeteaseStore.self) private var store
    @Environment(NeteaseContentCache.self) private var contentCache
    @Environment(\.dynamicTypeSize) private var typeSize
    @State private var refreshRevision = 0
    private var model: NeteasePageModel { contentCache.page(.home("", 0), revision: store.revision) }
    private var requestID: String { "\(store.revision)" }

    var body: some View {
        MainTabPage(title: "网易云音乐", onRefresh: { refreshRevision += 1; await load(refresh: true) }) {
            shortcuts
            NeteaseHomeSections(personal: model, refreshRevision: refreshRevision)
        }
        .task(id: requestID) {
            contentCache.prewarmShortcuts(store: store)
            if !model.hasLoaded { await load() }
        }
    }
    private func load(refresh: Bool = false) async {
        await model.load(api: store.api, route: nil, userID: store.profile?.userId, query: "", kind: 0,
                         library: store.library, refresh: refresh)
    }
    private var shortcuts: some View {
        let layout = typeSize.isAccessibilitySize
            ? AnyLayout(VStackLayout(spacing: 12))
            : AnyLayout(HStackLayout(alignment: .top, spacing: 12))
        return layout {
            DiscoveryShortcutButton(title: NeteaseRoute.radio.title) { starting in
                NeteaseFeaturedShortcutCard(kind: .radio, isLoading: starting)
            } start: {
                guard store.profile != nil else { store.showsLogin = true; return }
                let revision = store.revision
                let radio = contentCache.page(.route(.radio), revision: revision)
                if !radio.hasLoaded { await radio.load(api: store.api, route: .radio) }
                try Task.checkCancellation()
                guard store.revision == revision else { throw CancellationError() }
                if let error = radio.error { throw NeteaseRadioStartError(message: error) }
                let first = try await store.radio.start(with: radio.songs.map(\.track))
                try Task.checkCancellation()
                guard store.revision == revision else { throw CancellationError() }
                radio.reset()
                player.playRemoteDiscovery(first, providerID: "netease")
                nowPlaying.isPresented = true
            }
            NavigationLink(value: AppRoute.netease(.daily)) {
                NeteaseFeaturedShortcutCard(kind: .daily)
            }
            .buttonStyle(.plain)
            .accessibilityLabel(NeteaseRoute.daily.title)
        }
    }

}

private struct NeteaseRadioStartError: LocalizedError {
    let message: String
    var errorDescription: String? { message }
}

struct NeteaseCollectionView: View {
    let route: NeteaseRoute
    @Environment(NeteaseStore.self) private var store
    @Environment(PlayerStore.self) private var player
    @Environment(NeteaseContentCache.self) private var contentCache
    private var model: NeteasePageModel { contentCache.page(.route(route), revision: store.revision) }
    private var needsLogin: Bool { route.requiresLogin && store.profile == nil }
    private var isSongCollection: Bool { route.isSongCollection }
    private var contentRevision: Int { store.library.contentRevision(for: route) }
    private var artwork: URL? { model.artwork ?? model.songs.first?.album?.artworkURL }
    private var tracks: [Track] { model.songs.map(\.track) }
    private var sourceID: Int? {
        switch route { case .playlist(let id), .album(let id): id; default: nil }
    }
    private var supportsFavorite: Bool {
        switch route { case .album, .playlist: true; default: false }
    }
    private var collectionID: Int? { supportsFavorite ? sourceID : nil }
    /// 账号自带的「我喜欢的音乐」歌单：不能收藏自己的歌单，换成心动模式。
    private var isOwnLikedPlaylist: Bool {
        model.playlist?.specialType == 5 && model.playlist?.creator?.userId == store.profile?.userId
    }
    var body: some View {
        Group {
            if needsLogin {
                ScrollView {
                    ContentUnavailableView {
                        Label("登录网易云音乐", systemImage: "person.crop.circle")
                    } description: { Text("登录后查看\(route.title)。") } actions: {
                        Button("登录") { store.showsLogin = true }.buttonStyle(.borderedProminent).tint(DizzyPalette.accentFill).foregroundStyle(DizzyPalette.onAccent)
                    }
                }.dizzyPageBackground()
            } else if isSongCollection {
                AlbumDetailScrollView(artworkURL: artwork) {
                    LazyVStack(alignment: .leading, spacing: 0) {
                        AlbumHero(artworkURL: artwork, title: model.title.isEmpty ? route.title : model.title,
                                  metadata: model.hasLoaded ? "\(model.playlist?.trackCount ?? tracks.count) 首歌曲" : "歌曲数量", reservesTitleSpace: true, metadataIsPlaceholder: model.showsInitialSkeleton) {
                            Text(collectionSubtitle.isEmpty ? (model.showsInitialSkeleton ? "创作者" : " ") : collectionSubtitle)
                                .redacted(reason: model.showsInitialSkeleton && collectionSubtitle.isEmpty ? .placeholder : [])
                        } actions: {
                            AlbumPlaybackActions(isEmpty: tracks.isEmpty, play: { shuffled in
                                guard !tracks.isEmpty else { return }
                                player.play(tracks, startAt: shuffled ? Int.random(in: tracks.indices) : 0, sourceID: sourceID)
                                if player.isShuffled != shuffled { player.toggleShuffle() }
                            }) {
                                if route == .liked || isOwnLikedPlaylist {
                                    NeteaseHeartModeButton()
                                } else if supportsFavorite {
                                    NeteaseCollectionFavorite(playlist: model.playlist, album: model.album)
                                }
                            }.padding(.horizontal, 20)
                        }
                        if case .artist(let id) = route {
                            NavigationLink(value: AppRoute.netease(.artistAlbums(id))) { Label("查看全部专辑", systemImage: "square.stack") }
                                .padding(.horizontal, 20).padding(.bottom, 12)
                        }
                        if !model.detailDescription.isEmpty {
                            AlbumDescriptionExcerpt(text: model.detailDescription)
                                .padding(.horizontal, 20).padding(.bottom, 20)
                        }
                        NeteaseSongRows(songs: model.songs, sourceID: sourceID)
                        if !model.songs.isEmpty {
                            Text(trackSummary)
                                .font(.footnote).foregroundStyle(.secondary)
                                .padding(.horizontal, 20).padding(.top, 12)
                        }
                        if model.showsInitialSkeleton {
                            NeteaseSkeleton(layout: .songs)
                        } else {
                            NeteaseResultStatus(model: model, retry: { await load(append: model.more) })
                                .padding(20)
                        }
                    }.padding(.bottom, 32)
                }
            } else {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 20) {
                        if case .category = route { categoryMenu }
                        NeteaseResults(model: model) { await load(append: true) }
                    }.padding(20)
                }.dizzyPageBackground()
            }
        }
        .safeAreaPadding(.top, 5)
        .navigationTitle(isSongCollection ? "" : route.title)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar(.visible, for: .navigationBar)
        .toolbarBackground(.hidden, for: .navigationBar)
        .toolbar {
            if let collectionID, model.hasLoaded {
                let isAlbum: Bool = { if case .album = route { return true }; return false }()
                let title = model.title
                ToolbarItem(placement: .topBarTrailing) {
                    NeteaseDownloadButton(kind: isAlbum ? "album" : "playlist", id: collectionID,
                                          title: title, coverURL: artwork)
                }
            }
            if case .newSongs = route { ToolbarItem(placement: .topBarTrailing) { regionMenu } }
            if case .newAlbums = route { ToolbarItem(placement: .topBarTrailing) { regionMenu } }
            if route == .radio && !needsLogin {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("换一批", systemImage: "arrow.clockwise") { Task { await load() } }.disabled(model.loading)
                }
            }
        }
        .task(id: "\(store.revision)/\(contentRevision)") {
            if !needsLogin && (!model.hasLoaded || (route.respondsToLibraryChanges && model.libraryRevision != contentRevision)) { await load() }
        }
        .refreshable { if !needsLogin { await load(refresh: true) } }
    }
    private var trackSummary: String {
        let durations = tracks.compactMap(\.duration)
        var text = "\(tracks.count) 首歌曲"
        if durations.count == tracks.count && !tracks.isEmpty {
            text += "，\(Int((durations.reduce(0, +) / 60).rounded())) 分钟"
        }
        if !model.remaining.isEmpty { text += "，还有 \(model.remaining.count) 首待加载" }
        return text
    }
    private var collectionSubtitle: String {
        if case .album = route { return model.songs.first?.artists.map(\.name).joined(separator: " / ") ?? "" }
        switch route {
        case .daily: return "为你推荐"
        case .radio: return "发现下一首喜欢的音乐"
        case .artist: return "热门歌曲"
        case .newSongs(let region): return region.title
        case .liked: return "收藏在网易云账号中的歌曲"
        case .recent: return "网易云账号的最近播放记录"
        case .similar: return "发现相似的音乐"
        case .personalizedSongs: return "为你发现新音乐"
        default: return model.playlist?.creator?.nickname ?? "歌单"
        }
    }
    private func load(append: Bool = false, refresh: Bool = false) async {
        await model.load(api: store.api, route: route, userID: store.profile?.userId, append: append, library: store.library, refresh: refresh)
    }
    private var categoryMenu: some View {
        Menu("选择分类", systemImage: "line.3.horizontal.decrease") {
            ForEach(["全部", "华语", "欧美", "日语", "韩语", "流行", "摇滚", "电子", "民谣", "古典", "轻音乐", "ACG", "游戏", "学习", "运动", "治愈"], id: \.self) { name in
                NavigationLink(name, value: AppRoute.netease(.category(name)))
            }
        }
    }
    private var regionMenu: some View {
        Menu("地区", systemImage: "globe") {
            ForEach(NeteaseRegion.allCases) { region in
                NavigationLink(region.title, value: AppRoute.netease(regionRoute(region)))
            }
        }
    }
    private func regionRoute(_ region: NeteaseRegion) -> NeteaseRoute {
        if case .newAlbums = route { return .newAlbums(region) }
        return .newSongs(region)
    }
}

struct NeteaseResults: View {
    let model: NeteasePageModel
    var skeletonLayout: NeteaseSkeletonLayout = .grid
    let loadMore: () async -> Void
    var body: some View {
        if !model.playlists.isEmpty || !model.albums.isEmpty {
            LazyVGrid(columns: DizzyGrid.columns, alignment: .leading, spacing: 22) {
                ForEach(model.playlists) { item in
                    NavigationLink(value: AppRoute.netease(.playlist(item.id))) { card(item.name, url: item.artworkURL) }.buttonStyle(.plain)
                }
                ForEach(model.albums) { item in
                    NavigationLink(value: AppRoute.netease(.album(item.id))) { card(item.name, url: item.artworkURL) }.buttonStyle(.plain)
                }
            }
        }
        if !model.artists.isEmpty {
            LazyVGrid(columns: DizzyGrid.columns, spacing: 22) {
                ForEach(model.artists) { artist in
                    NavigationLink(value: AppRoute.netease(.artist(artist.id))) { card(artist.name, url: artist.artworkURL) }.buttonStyle(.plain)
                }
            }
        }
        NeteaseSongRows(songs: model.songs)
        NeteaseResultStatus(model: model, skeletonLayout: skeletonLayout, retry: loadMore)
    }
    private func card(_ title: String, url: URL?) -> some View {
        DiscCard(disc: DiscSummary(id: url?.absoluteString ?? title, title: title, coverURL: url), showsLabel: false)
    }
}

struct NeteaseSongRows: View {
    let songs: [NeteaseSong]
    var sourceID: Int? = nil
    var compact = false
    @Environment(PlayerStore.self) private var player
    @Environment(NeteaseStore.self) private var store
    @Environment(\.openRoute) private var openRoute
    @Environment(DownloadStore.self) private var downloads
    @Environment(OfflineLibraryStore.self) private var library
    @Environment(AccountLibraryMirror.self) private var mirror
    @State private var downloadedKeys: Set<RemoteTrackKey> = []
    @State private var showsDownloads = false
    @State private var error: String?
    var body: some View {
        LazyVStack(spacing: 0) {
            ForEach(Array(songs.enumerated()), id: \.element.id) { index, song in
                AlbumTrackRow(track: song.track, displayNumber: String(index + 1), isDownloaded: song.track.remoteKey.map(downloadedKeys.contains) == true, additionalActions: actions(song), compact: compact) {
                    player.play(songs.map(\.track), startAt: index, sourceID: sourceID)
                }
            }
        }
        .task(id: store.revision) { if store.profile != nil && !songs.isEmpty { try? await store.library.loadLikes() } }
        .task(id: "\(library.contentRevision)/\(songs.map(\.id))") {
            var keys = Set<RemoteTrackKey>()
            for id in Set(songs.compactMap { $0.album?.id }) {
                if let available = try? await library.localTrackKeys(provider: "netease", collectionID: String(id)) { keys.formUnion(available) }
            }
            guard !Task.isCancelled else { return }
            downloadedKeys = keys
        }
        .sheet(isPresented: $showsDownloads) { DownloadQueueSheet() }
        .alert("操作失败", isPresented: Binding(get: { error != nil }, set: { if !$0 { error = nil } })) {
            Button("好", role: .cancel) { error = nil }
        } message: { Text(error ?? "") }
    }
    private func actions(_ song: NeteaseSong) -> [AlbumRowAction] {
        var actions: [AlbumRowAction] = [
            .init(id: "similar", title: "相似歌曲", systemImage: "music.note.list") { openRoute(.netease(.similar(song.id))) }
        ]
        let downloaded = song.track.remoteKey.map(downloadedKeys.contains) == true
        actions.append(.init(id: "download", title: downloaded ? "已下载" : "下载", systemImage: downloaded ? "checkmark.circle" : "arrow.down.circle", disabled: downloaded) {
            Task {
                await downloads.enqueueNetease(kind: "single", id: song.id, title: song.name, coverURL: song.album?.artworkURL,
                                               quality: store.playbackSettings.download)
                showsDownloads = true
            }
        })
        for artist in song.artists where artist.id > 0 {
            actions.append(.init(id: "artist/\(artist.id)", title: "歌手：\(artist.name)", systemImage: "person") { openRoute(.netease(.artist(artist.id))) })
        }
        if let album = song.album, album.id > 0 {
            actions.append(.init(id: "album", title: "前往专辑", systemImage: "square.stack") { openRoute(.netease(.album(album.id))) })
        }
        return actions
    }
}

struct NeteaseResultStatus: View {
    let model: NeteasePageModel
    var skeletonLayout: NeteaseSkeletonLayout = .songs
    let retry: () async -> Void
    var body: some View {
        if let error = model.error {
            LoadFailureView(message: error, retry: retry)
        }
        if model.showsInitialSkeleton {
            NeteaseSkeleton(layout: skeletonLayout)
        }
        else if model.loading {
            // Refresh keeps the existing content; pagination reserves the next content block.
            if model.more { NeteaseSkeleton(layout: skeletonLayout) }
        }
        // 出错时只显示上面的重试，不自动再请求。
        else if model.more && model.error == nil {
            AutoLoadMoreFooter(progress: model.songs.count + model.albums.count + model.playlists.count + model.artists.count, load: retry) {
                NeteaseSkeleton(layout: skeletonLayout)
            }
        }
        else if model.isEmpty && model.error == nil {
            Text("这里还没有内容。")
                .font(.subheadline).foregroundStyle(DizzyPalette.mutedText)
                .frame(maxWidth: .infinity).padding(.vertical, 60)
        }
    }
}

// Adapted from MeloX Features/Search/SearchView.swift and Features/Artist/ArtistDetailView.swift (GPL-3.0).

/// 一首网易云歌曲的列表行：点一下从这首开始播放整组，长按有相似歌曲、下载、歌手、专辑。
struct NeteaseTrackRow: View {
    let song: NeteaseSong
    let songs: [NeteaseSong]
    var index: Int?
    var showsArtwork = true
    var sourceID: Int?
    @Environment(PlayerStore.self) private var player
    @Environment(NeteaseStore.self) private var store
    @Environment(DownloadStore.self) private var downloads
    @Environment(OfflineLibraryStore.self) private var library
    @Environment(\.openRoute) private var openRoute

    var body: some View {
        let track = song.track
        let downloaded = library.localFile(for: track) != nil
        Button {
            player.play(songs.map(\.track), startAt: songs.firstIndex(of: song) ?? 0, sourceID: sourceID)
        } label: {
            TrackListRow(track: track, index: index, showsArtwork: showsArtwork, isDownloaded: downloaded,
                         additionalActions: actions(downloaded: downloaded))
        }
        .buttonStyle(.plain)
    }

    private func actions(downloaded: Bool) -> [AlbumRowAction] {
        var actions: [AlbumRowAction] = [
            .init(id: "similar", title: "相似歌曲", systemImage: "music.note.list") { openRoute(.netease(.similar(song.id))) },
            .init(id: "download", title: downloaded ? "已下载" : "下载", systemImage: downloaded ? "checkmark.circle" : "arrow.down.circle",
                  disabled: downloaded) {
                Task {
                    await downloads.enqueueNetease(kind: "single", id: song.id, title: song.name, coverURL: song.album?.artworkURL,
                                                   quality: store.playbackSettings.download)
                }
            },
        ]
        for artist in song.artists where artist.id > 0 {
            actions.append(.init(id: "artist/\(artist.id)", title: "歌手：\(artist.name)", systemImage: "person") {
                openRoute(.netease(.artist(artist.id)))
            })
        }
        if let album = song.album, album.id > 0 {
            actions.append(.init(id: "album", title: "前往专辑", systemImage: "square.stack") { openRoute(.netease(.album(album.id))) })
        }
        return actions
    }
}

/// 统一搜索里的「网易云」一组：未登录时一行提示，前五首歌，下面是歌单、专辑、歌手三个入口。
struct NeteaseSearchSection: View {
    let query: String
    @Environment(NeteaseStore.self) private var store
    @Environment(NeteaseContentCache.self) private var contentCache
    private var model: NeteasePageModel { contentCache.page(.home(query, 1), revision: store.revision) }

    var body: some View {
        let songs = Array(model.songs.prefix(5))
        VStack(alignment: .leading, spacing: 8) {
            SearchGroup(title: NeteaseModule.metadata.title,
                        allResults: model.songs.isEmpty ? nil : .netease(.search(query, 1))) {
                if store.profile == nil {
                    SearchCardRow(isLast: false, separatorInset: 0) {
                        HStack(spacing: 4) {
                            Text("未登录 · 部分歌曲只能试听 ·").foregroundStyle(.secondary)
                            Button("登录") { store.showsLogin = true }.fontWeight(.semibold)
                        }
                        .font(.footnote)
                    }
                }
                if let error = model.error, model.songs.isEmpty {
                    SearchCardRow(isLast: true) {
                        SearchSectionFailure(title: "网易云搜索失败", message: error) { await load() }
                    }
                } else if model.songs.isEmpty && (!model.hasLoaded || model.loading) {
                    SearchCardRow(isLast: true) { SearchSectionMessage(text: "正在搜索…", isLoading: true) }
                } else if model.songs.isEmpty {
                    SearchCardRow(isLast: true) { SearchSectionMessage(text: "网易云没有和「\(query)」相关的歌曲。") }
                } else {
                    ForEach(Array(songs.enumerated()), id: \.element.id) { index, song in
                        SearchCardRow(isLast: index == songs.count - 1) { NeteaseTrackRow(song: song, songs: model.songs) }
                    }
                }
            }
            Grid(horizontalSpacing: 8) {
                GridRow {
                    kindLink("歌单", kind: 1000)
                    kindLink("专辑", kind: 10)
                    kindLink("歌手", kind: 100)
                }
            }
        }
        .task(id: "\(store.revision)/\(query)") { if !model.hasLoaded { await load() } }
    }

    private func kindLink(_ title: LocalizedStringKey, kind: Int) -> some View {
        NavigationLink(value: AppRoute.netease(.search(query, kind))) {
            HStack {
                Text(title).font(.subheadline.weight(.semibold)).foregroundStyle(DizzyPalette.text)
                Spacer(minLength: 4)
                Image(systemName: "chevron.right").font(.caption.weight(.semibold)).foregroundStyle(.tertiary)
            }
            .padding(.horizontal, 12)
            .frame(maxWidth: .infinity, minHeight: 44)
            .background(DizzyPalette.surface, in: .rect(cornerRadius: 12))
            .contentShape(.rect(cornerRadius: 12))
        }
        .buttonStyle(.plain)
    }

    private func load() async {
        await model.load(api: store.api, userID: store.profile?.userId, query: query, kind: 1, library: store.library)
    }
}

/// 「查看全部」：照搬 MeloX 的搜索结果，普通列表，顶部分段切换歌曲、专辑、歌手、歌单，滚到底继续加载。
struct NeteaseSearchPage: View {
    let query: String
    @Environment(NeteaseStore.self) private var store
    @Environment(NeteaseContentCache.self) private var contentCache
    @State private var kind: Int

    init(query: String, kind: Int = 1) {
        self.query = query
        _kind = State(initialValue: kind)
    }

    private var model: NeteasePageModel { contentCache.page(.home(query, kind), revision: store.revision) }

    var body: some View {
        List {
            Picker("类型", selection: $kind) {
                Text("歌曲").tag(1)
                Text("专辑").tag(10)
                Text("歌手").tag(100)
                Text("歌单").tag(1000)
            }
            .pickerStyle(.segmented)
            .listRowSeparator(.hidden)
            switch kind {
            case 1:
                ForEach(model.songs) { song in NeteaseTrackRow(song: song, songs: model.songs).onAppear { loadMore(after: song.id, in: model.songs.map(\.id)) } }
            case 10:
                ForEach(model.albums) { album in
                    NavigationLink(value: AppRoute.netease(.album(album.id))) {
                        SearchMediaRow(title: album.name, subtitle: album.artist?.name, artworkURL: album.artworkURL)
                    }
                    .onAppear { loadMore(after: album.id, in: model.albums.map(\.id)) }
                }
            case 100:
                ForEach(model.artists) { artist in
                    NavigationLink(value: AppRoute.netease(.artist(artist.id))) {
                        SearchMediaRow(title: artist.name, subtitle: artist.alias?.first, artworkURL: artist.artworkURL, circular: true)
                    }
                    .onAppear { loadMore(after: artist.id, in: model.artists.map(\.id)) }
                }
            default:
                ForEach(model.playlists) { playlist in
                    NavigationLink(value: AppRoute.netease(.playlist(playlist.id))) {
                        SearchMediaRow(title: playlist.name, subtitle: playlist.trackCount.map { "\($0) 首" }, artworkURL: playlist.artworkURL)
                    }
                    .onAppear { loadMore(after: playlist.id, in: model.playlists.map(\.id)) }
                }
            }
            // 状态放在结果区，避免空结果或失败时遮住上方的类型切换。
            if let error = model.error {
                SearchSectionFailure(title: "网易云搜索失败", message: error) {
                    await load(append: model.hasLoaded)
                }
                .listRowSeparator(.hidden)
            } else if model.loading || !model.hasLoaded {
                HStack { Spacer(); ProgressView("正在搜索…"); Spacer() }.listRowSeparator(.hidden)
            } else if model.isEmpty {
                ContentUnavailableView.search(text: query).listRowSeparator(.hidden)
            }
        }
        .listStyle(.plain)
        .navigationTitle("网易云 · 「\(query)」")
        .navigationBarTitleDisplayMode(.inline)
        .task(id: "\(store.revision)/\(query)/\(kind)") { if !model.hasLoaded { await load() } }
    }

    private func loadMore(after id: Int, in ids: [Int]) {
        guard id == ids.last, model.more, !model.loading else { return }
        Task { await load(append: true) }
    }

    private func load(append: Bool = false) async {
        await model.load(api: store.api, userID: store.profile?.userId, query: query, kind: kind,
                         append: append, library: store.library)
    }
}

/// 网易云歌手页：背景取头像颜色（与专辑页同一套外观），依次是大头像与播放按钮、热门歌曲、专辑、简介。
struct NeteaseArtistDetailView: View {
    let id: Int
    @Environment(NeteaseStore.self) private var store
    @Environment(PlayerStore.self) private var player
    @State private var artist: NeteaseArtist?
    @State private var songs: [NeteaseSong] = []
    @State private var albums: [NeteaseAlbum] = []
    @State private var failure: String?
    @State private var reloadToken = 0

    var body: some View {
        AlbumDetailScrollView(artworkURL: artist?.artworkURL) {
            if let artist {
                content(artist)
            } else if let failure {
                LoadFailureView(message: failure) { self.failure = nil; reloadToken += 1 }
                    .padding(.top, 120)
            } else {
                ProgressView().frame(maxWidth: .infinity).padding(.top, 200)
            }
        }
        .navigationTitle("")
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(.hidden, for: .navigationBar)
        .task(id: reloadToken) {
            guard artist == nil else { return }
            await load()
        }
    }

    private func content(_ artist: NeteaseArtist) -> some View {
        let subtitle = ([artist.alias?.joined(separator: " / ")].compactMap { $0 }.filter { !$0.isEmpty }
            + (albums.isEmpty ? [] : ["\(albums.count) 张专辑"])).joined(separator: " · ")
        return LazyVStack(alignment: .leading, spacing: 28) {
            ProfileHero(artworkURL: artist.artworkURL, title: artist.name, subtitle: subtitle) {
                AlbumPlaybackActions(isEmpty: songs.isEmpty) { shuffled in
                    let tracks = songs.map(\.track)
                    guard !tracks.isEmpty else { return }
                    player.play(tracks, startAt: shuffled ? Int.random(in: tracks.indices) : 0, sourceID: artist.id)
                    if player.isShuffled != shuffled { player.toggleShuffle() }
                }
            }
            if !songs.isEmpty {
                VStack(alignment: .leading, spacing: 4) {
                    ProfileSectionHeader(title: "热门歌曲", allTitle: songs.count > 5 ? "全部 \(songs.count) 首" : nil) {
                        NeteaseArtistSongsPage(name: artist.name, artistID: artist.id, songs: songs)
                    }
                    NeteaseSongRows(songs: Array(songs.prefix(5)), sourceID: artist.id)
                }
            }
            if !albums.isEmpty {
                VStack(alignment: .leading, spacing: 12) {
                    ProfileSectionHeader(title: "专辑", allTitle: "全部") {
                        NeteaseCollectionView(route: .artistAlbums(artist.id))
                    }
                    NeteaseCoverShelf(albums: albums).padding(.horizontal, 20)
                }
            }
            if let brief = artist.briefDesc, !brief.isEmpty {
                ExpandableText(title: "简介", text: brief).padding(.horizontal, 20)
            }
        }
        .padding(.bottom, 32)
    }

    private func load() async {
        do {
            async let detail = store.api.artist(id)
            async let albumPage = store.api.artistAlbums(id)
            let (loaded, page) = try await (detail, albumPage)
            songs = loaded.songs
            albums = page.items
            artist = loaded.artist
        } catch is CancellationError {
        } catch {
            failure = error.localizedDescription
        }
    }
}

/// 「全部 N 首」：歌手的全部热门歌曲。
struct NeteaseArtistSongsPage: View {
    let name: String
    let artistID: Int
    let songs: [NeteaseSong]

    var body: some View {
        List {
            ForEach(Array(songs.enumerated()), id: \.element.id) { index, song in
                NeteaseTrackRow(song: song, songs: songs, index: index, showsArtwork: false, sourceID: artistID)
            }
        }
        .listStyle(.plain)
        .navigationTitle("\(name) · 热门歌曲")
        .navigationBarTitleDisplayMode(.inline)
    }
}
