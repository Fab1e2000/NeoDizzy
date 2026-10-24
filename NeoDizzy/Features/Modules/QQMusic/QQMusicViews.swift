import SwiftUI

struct QQMusicSearchSection: View {
    let query: String
    @Environment(QQMusicStore.self) private var store
    @State private var model = QQMusicPageModel()

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            SearchGroup(title: "QQ 音乐", allResults: model.songs.isEmpty ? nil : .qqmusic(.typedSearch(query, .songs))) {
                if let error = model.error {
                    SearchCardRow {
                        SearchSectionFailure(title: "QQ 音乐搜索失败", message: error) { await load() }
                    }
                } else if model.songs.isEmpty && (!model.hasLoaded || model.loading) {
                    SearchCardRow { SearchSectionMessage(text: "正在搜索…", isLoading: true) }
                } else if model.songs.isEmpty {
                    SearchCardRow { SearchSectionMessage(text: "QQ 音乐没有和「\(query)」相关的歌曲。") }
                } else {
                    QQMusicSongRows(songs: Array(model.songs.prefix(5)))
                }
            }
            Grid(horizontalSpacing: 8) {
                GridRow {
                    kindLink(.playlists)
                    kindLink(.albums)
                    kindLink(.artists)
                }
            }
        }
        .task(id: "\(store.revision)/\(query)") { await load() }
    }

    private func kindLink(_ kind: QQMusicSearchKind) -> some View {
        NavigationLink(value: AppRoute.qqmusic(.typedSearch(query, kind))) {
            HStack {
                Text(kind.title).font(.subheadline.weight(.semibold)).foregroundStyle(DizzyPalette.text)
                Spacer(minLength: 4)
                Image(systemName: "chevron.right").font(.caption.weight(.semibold)).foregroundStyle(.tertiary)
            }
            .padding(.horizontal, 12).frame(maxWidth: .infinity, minHeight: 44)
            .background(DizzyPalette.surface, in: .rect(cornerRadius: 12))
            .contentShape(.rect(cornerRadius: 12))
        }.buttonStyle(.plain)
    }

    private func load() async { await model.load(store: store, route: .search(query)) }
}

struct QQMusicCollectionView: View {
    let route: QQMusicRoute
    @Environment(QQMusicStore.self) private var store
    @Environment(PlayerStore.self) private var player
    @Environment(QQMusicContentCache.self) private var cache
    @Environment(AccountLibraryMirror.self) private var accountLibrary
    @Environment(SavedLibraryStore.self) private var savedLibrary
    @Environment(\.scenePhase) private var scenePhase
    @State private var foregroundRevision = 0
    private var model: QQMusicPageModel { cache.page(route, revision: store.revision, library: store.library) }

    private var isSearch: Bool { if case .search = route { true } else { false } }
    private var isDirectory: Bool {
        switch route { case .artists, .artistAlbums, .newAlbums: true; default: false }
    }
    private var contentRevision: Int { QQMusicPageModel.contentRevision(store: store, route: route) }
    private var artwork: URL? { model.artwork ?? libraryArtwork }
    private var libraryArtwork: URL? {
        let kind: MirroredCollection.Kind
        let id: String
        switch route {
        case .album(let albumID): kind = .album; id = albumID
        case .playlist(let playlistID): kind = .playlist; id = playlistID
        default: return nil
        }
        return accountLibrary.collections.first {
            $0.providerID == "qqmusic" && $0.kind == kind && $0.itemID == id
        }?.coverURL ?? savedLibrary.items.first {
            $0.providerID == "qqmusic" && $0.kind.rawValue == kind.rawValue && $0.itemID == id
        }?.coverURL
    }
    private var isAlbum: Bool { if case .album = route { true } else { false } }
    private var descriptionTitle: String? {
        switch route { case .album: "专辑介绍"; case .playlist: "歌单介绍"; default: nil }
    }
    private var needsLogin: Bool { route == .daily && store.credential == nil }
    private var tracks: [Track] { model.songs.map(\.track) }

    var body: some View {
        Group {
            if needsLogin {
                ContentUnavailableView {
                    Label("登录 QQ 音乐", systemImage: "person.crop.circle")
                } description: {
                    Text("登录后查看为你更新的每日30首。")
                } actions: {
                    Button("登录") { store.showsAccount = true }.buttonStyle(.borderedProminent)
                }
                .dizzyPageBackground()
            } else if isDirectory {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 12) {
                        QQMusicAlbumRows(albums: model.albums)
                        QQMusicArtistRows(artists: model.artists)
                        QQMusicResultStatus(model: model, isEmpty: model.albums.isEmpty && model.artists.isEmpty) {
                            await load(append: model.retryAppend)
                        }
                        paginationFooter
                    }.padding(20)
                }.dizzyPageBackground()
            } else if isSearch {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 8) {
                        Text(model.title).font(.title2.bold())
                        QQMusicSongRows(songs: model.songs)
                        status
                        paginationFooter
                    }.padding(20)
                }.dizzyPageBackground()
            } else {
                AlbumDetailScrollView(artworkURL: artwork) {
                    LazyVStack(alignment: .leading, spacing: 0) {
                        AlbumHero(artworkURL: artwork, title: model.title.isEmpty ? route.title : model.title,
                                  metadata: model.hasLoaded ? "\(tracks.count) 首歌曲" : "正在加载…") {
                            Text(isAlbum ? model.songs.first?.artist ?? "QQ 音乐" : "QQ 音乐")
                        } actions: {
                            AlbumPlaybackActions(isEmpty: tracks.isEmpty, play: play) {
                                collectionActions
                            }
                                .padding(.horizontal, 20)
                        }
                        if let descriptionTitle, !model.detailDescription.isEmpty {
                            AlbumDescriptionExcerpt(text: model.detailDescription, title: model.title,
                                                    subtitle: isAlbum ? model.songs.first?.artist : nil,
                                                    accessibilityTitle: descriptionTitle)
                                .padding(.horizontal, 20)
                                .padding(.bottom, 20)
                        }
                        if case .artist(let mid) = route {
                            NavigationLink(value: AppRoute.qqmusic(.artistAlbums(mid))) {
                                Label("查看全部专辑", systemImage: "square.stack")
                            }.padding(.horizontal, 20).padding(.bottom, 12)
                            if !model.biography.isEmpty {
                                DisclosureGroup("歌手简介") { Text(model.biography).font(.subheadline).foregroundStyle(.secondary) }
                                    .padding(.horizontal, 20).padding(.bottom, 16)
                            }
                        }
                        if case .song = route, let song = model.songs.first, !song.albumMid.isEmpty {
                            AlbumNavigationLink(value: AppRoute.qqmusic(.album(song.albumMid)), artworkURL: song.coverURL,
                                                zoomsFromArtwork: false) {
                                Label(song.albumTitle.isEmpty ? "前往专辑" : song.albumTitle, systemImage: "square.stack")
                            }.padding(.horizontal, 20).padding(.bottom, 12)
                        }
                        QQMusicSongRows(songs: model.songs, numbered: isAlbum).padding(.horizontal, 20)
                        status.padding(20)
                        paginationFooter.padding(.horizontal, 20)
                    }.padding(.bottom, 32)
                }
            }
        }
        .navigationTitle(isSearch ? "搜索" : isDirectory ? route.title : "")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar(.visible, for: .navigationBar)
        .toolbarBackground(.hidden, for: .navigationBar)
        .task(id: RequestIdentity(route: route, revision: store.revision, foreground: foregroundRevision, content: contentRevision)) {
            if !needsLogin && (!model.hasLoaded || model.libraryRevision != contentRevision || route == .daily && model.needsDailyRefresh) {
                await load()
                // A shared request started yesterday still belongs to yesterday.
                if route == .daily && model.needsDailyRefresh && model.error == nil && !Task.isCancelled {
                    await load()
                }
            }
        }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active && route == .daily { foregroundRevision += 1 }
        }
        .refreshable { await load() }
    }

    @ViewBuilder private var collectionActions: some View {
        switch route {
        case .album(let id):
            QQMusicCollectionFavorite(collection: collection(id), kind: .album)
            #if os(iOS)
            QQMusicDownloadButton(kind: "album", id: id, title: model.title, coverURL: model.artwork)
            #endif
        case .playlist(let id):
            QQMusicCollectionFavorite(collection: collection(id), kind: .playlist)
            #if os(iOS)
            QQMusicDownloadButton(kind: "playlist", id: id, title: model.title, coverURL: model.artwork)
            #endif
        case .song(let mid):
            #if os(iOS)
            QQMusicDownloadButton(kind: "song", id: mid, title: model.title, coverURL: model.artwork)
            #endif
        default: EmptyView()
        }
    }

    private func collection(_ id: String) -> QQMusicCollection {
        QQMusicCollection(id: id, title: model.title, coverURL: model.artwork, songs: model.songs)
    }

    private var status: some View {
        QQMusicResultStatus(model: model, isEmpty: model.songs.isEmpty) {
            await load(append: model.retryAppend)
        }
    }

    @ViewBuilder private var paginationFooter: some View {
        if model.more && model.error == nil && !model.loading {
            AutoLoadMoreFooter(progress: model.songs.count + model.albums.count + model.artists.count,
                               load: { await load(append: true) }) {
                ProgressView().frame(maxWidth: .infinity).padding(.vertical, 24)
            }
        }
    }

    private func load(append: Bool = false) async {
        guard !needsLogin else { return }
        await model.load(store: store, route: route, append: append)
    }

    private func play(shuffled: Bool) {
        guard store.active, !tracks.isEmpty else { return }
        player.play(tracks, startAt: shuffled ? Int.random(in: tracks.indices) : 0)
        if player.isShuffled != shuffled { player.toggleShuffle() }
    }

    private struct RequestIdentity: Hashable {
        let route: QQMusicRoute
        let revision: Int
        let foreground: Int
        let content: Int
    }
}

struct QQMusicSongRows: View {
    let songs: [QQMusicSong]
    var numbered = false
    @Environment(QQMusicStore.self) private var store
    @Environment(PlayerStore.self) private var player
    @Environment(\.openRoute) private var openRoute
    @State private var albumNavigation = AlbumNavigationPreparation()
    #if os(iOS)
    @Environment(DownloadStore.self) private var downloads
    @State private var showsDownloadQueue = false
    #endif

    var body: some View {
        ForEach(Array(songs.enumerated()), id: \.element.mid) { index, song in
            SongRow(track: song.track, style: numbered ? .numbered(String(index + 1)) : .artwork,
                    actions: actions(song)) {
                guard store.active else { return }
                player.play(songs.map(\.track), startAt: index)
            }
        }
        #if os(iOS)
        .sheet(isPresented: $showsDownloadQueue) { DownloadQueueSheet() }
        #endif
        .preparedAlbumNavigation(albumNavigation)
        .onChange(of: songs.map(\.mid)) { _, _ in albumNavigation.cancel() }
        .onChange(of: store.revision) { _, _ in albumNavigation.cancel() }
    }

    private func actions(_ song: QQMusicSong) -> [SongRowAction] {
        var actions: [SongRowAction] = [
            .init(id: "song", title: "歌曲详情", systemImage: "music.note") {
                openRoute(.qqmusic(.song(song.mid)))
            }
        ]
        if !song.albumMid.isEmpty {
            actions.append(.init(id: "album", title: "前往专辑", systemImage: "square.stack") {
                guard store.active else { return }
                if let route = albumNavigation.begin(.qqmusic(.album(song.albumMid)), artworkURL: QQMusicSong.cover(albumMid: song.albumMid)) {
                    openRoute(route)
                }
            })
        }
        actions.append(.init(id: "similar", title: "相似歌曲", systemImage: "sparkles") {
            openRoute(.qqmusic(.similar(song.mid)))
        })
        for singer in song.singers {
            actions.append(.init(id: "artist-\(singer.id)", title: "歌手 · \(singer.name)", systemImage: "person") {
                openRoute(.qqmusic(.artist(singer.id)))
            })
        }
        #if os(iOS)
        actions.append(.init(id: "download", title: "下载", systemImage: "arrow.down.circle") {
            Task {
                await downloads.enqueueQQMusicSong(song.track, quality: store.playbackSettings.quality)
                showsDownloadQueue = true
            }
        })
        #endif
        return actions
    }
}

private struct QQMusicResultStatus: View {
    let model: QQMusicPageModel
    let isEmpty: Bool
    var layout: ContentSkeletonLayout = .songs
    let retry: () async -> Void

    var body: some View {
        if let error = model.error {
            LoadFailureView(message: error, retry: retry)
        } else if isEmpty && (!model.hasLoaded || model.loading) {
            ContentSkeleton(layout: layout)
        } else if model.loading {
            ProgressView().frame(maxWidth: .infinity).padding(.vertical, 24)
        } else if isEmpty {
            ContentUnavailableView("暂无内容", systemImage: "music.note.list")
        }
    }
}

struct QQMusicSearchPage: View {
    let query: String
    @State private var kind: QQMusicSearchKind
    @Environment(QQMusicStore.self) private var store
    @Environment(QQMusicContentCache.self) private var cache

    // The destination's requested kind seeds selection once; the user owns it thereafter.
    init(query: String, kind: QQMusicSearchKind = .songs) {
        self.query = query
        _kind = State(initialValue: kind)
    }

    private var route: QQMusicRoute { .typedSearch(query, kind) }
    private var model: QQMusicPageModel { cache.page(route, revision: store.revision) }
    private var itemIDs: [String] {
        switch kind {
        case .songs: model.songs.map(\.mid)
        case .albums: model.albums.map(\.id)
        case .artists: model.artists.map(\.id)
        case .playlists: model.playlists.map(\.id)
        }
    }

    var body: some View {
        List {
            Picker("类型", selection: $kind) {
                ForEach(QQMusicSearchKind.allCases, id: \.self) { Text($0.title).tag($0) }
            }
            .pickerStyle(.segmented).listRowSeparator(.hidden)
            Group {
                switch kind {
                case .songs: QQMusicSongRows(songs: model.songs)
                case .albums: QQMusicAlbumRows(albums: model.albums)
                case .artists: QQMusicArtistRows(artists: model.artists)
                case .playlists:
                    ForEach(model.playlists) { playlist in
                        AlbumNavigationLink(value: AppRoute.qqmusic(.playlist(playlist.id)), artworkURL: playlist.coverURL) {
                            SearchMediaRow(title: playlist.title, subtitle: nil, artworkURL: playlist.coverURL, showsChevron: false)
                        }.buttonStyle(.plain)
                    }
                }
            }.songListRow().listRowSeparator(.hidden)
            QQMusicResultStatus(model: model, isEmpty: itemIDs.isEmpty) { await load(append: model.retryAppend) }
                .listRowSeparator(.hidden)
            if model.more && model.error == nil && !model.loading {
                ProgressView().frame(maxWidth: .infinity).listRowSeparator(.hidden)
                    .task(id: itemIDs.last) { await load(append: true) }
            }
        }
        .listStyle(.plain)
        .navigationTitle("QQ 音乐 · 「\(query)」")
        .navigationBarTitleDisplayMode(.inline)
        .task(id: "\(store.revision)/\(query)/\(kind.rawValue)") { if !model.hasLoaded { await load() } }
        .refreshable { await load() }
    }

    private func load(append: Bool = false) async { await model.load(store: store, route: route, append: append) }
}

struct QQMusicAlbumRows: View {
    let albums: [QQMusicAlbum]
    var body: some View {
        ForEach(albums) { album in
            AlbumNavigationLink(value: AppRoute.qqmusic(.album(album.id)), artworkURL: QQMusicSong.cover(albumMid: album.id),
                                sourceArtworkURL: album.coverURL) {
                SearchMediaRow(title: album.title,
                               subtitle: [album.artist, album.releaseDate].filter { !$0.isEmpty }.joined(separator: " · "),
                               artworkURL: album.coverURL, showsChevron: false)
            }.buttonStyle(.plain)
        }
    }
}

struct QQMusicArtistRows: View {
    let artists: [QQMusicArtist]
    var body: some View {
        ForEach(artists) { artist in
            NavigationLink(value: AppRoute.qqmusic(.artist(artist.id))) {
                SearchMediaRow(title: artist.name, subtitle: artist.subtitle.isEmpty ? nil : artist.subtitle,
                               artworkURL: artist.coverURL, circular: true, showsChevron: false)
            }.buttonStyle(.plain)
        }
    }
}

struct QQMusicNewAlbumsPage: View {
    @State private var area: Int
    init(area: Int = 1) { _area = State(initialValue: area) }
    var body: some View {
        QQMusicCollectionView(route: .newAlbums(area))
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Picker("地区", selection: $area) {
                        Text("内地").tag(1)
                        Text("港台").tag(2)
                        Text("欧美").tag(3)
                        Text("韩国").tag(4)
                        Text("日本").tag(5)
                        Text("其他").tag(6)
                    }
                }
            }
    }
}
