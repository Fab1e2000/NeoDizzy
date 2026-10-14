import SwiftUI

struct NeteaseHomeView: View {
    @Environment(PlayerStore.self) private var player
    @Environment(NowPlayingPresentation.self) private var nowPlaying
    @Environment(NeteaseStore.self) private var store
    @Environment(NeteaseContentCache.self) private var contentCache
    @State private var query = ""
    @State private var submitted = ""
    @State private var kind = 1
    @State private var refreshRevision = 0
    @Environment(\.dynamicTypeSize) private var typeSize
    private var requestKind: Int { submitted.isEmpty ? 0 : kind }
    private var model: NeteasePageModel {
        contentCache.page(.home(submitted, requestKind), revision: store.revision)
    }
    private var requestID: String { "\(store.revision)/\(submitted)/\(requestKind)" }

    var body: some View {
        MainTabPage(title: "网易云音乐", onRefresh: { refreshRevision += 1; await load(refresh: true) }) {
            DiscoverSearchBar(text: $query, placeholder: "搜索歌曲、歌单、专辑、歌手") {
                submitted = query.trimmingCharacters(in: .whitespacesAndNewlines)
                if !submitted.isEmpty { kind = 1 }
            }
            if submitted.isEmpty {
                shortcuts
                NeteaseHomeSections(personal: model, refreshRevision: refreshRevision)
            } else {
                DiscoveryCategoryPicker(selection: $kind, options: [
                    (1, "歌曲"), (1000, "歌单"), (10, "专辑"), (100, "歌手")
                ])
                NeteaseResults(model: model, skeletonLayout: kind == 1 ? .songs : .grid) { await load(append: true) }
            }
        }
        .task(id: requestID) {
            contentCache.prewarmShortcuts(store: store)
            if !model.hasLoaded { await load() }
        }
        .scrollDismissesKeyboard(.interactively)
        .onChange(of: query) { _, value in
            if value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { submitted = ""; kind = 1 }
        }
    }
    private func load(append: Bool = false, refresh: Bool = false) async {
        await model.load(api: store.api, route: nil,
                         userID: store.profile?.userId, query: submitted, kind: requestKind, append: append,
                         library: store.library, refresh: refresh)
    }
    private var shortcuts: some View {
        let entries: [(NeteaseRoute, String)] = [(.daily, "calendar"), (.radio, "dot.radiowaves.left.and.right"), (.charts, "chart.bar"), (.myPlaylists, "music.note.list")]
        return LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 12), count: typeSize.isAccessibilitySize ? 1 : 2), spacing: 12) {
            ForEach(entries, id: \.0) { entry in
                if entry.0 == .radio {
                    DiscoveryShortcutButton(title: entry.0.title, systemImage: entry.1) {
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
                } else {
                NavigationLink(value: AppRoute.netease(entry.0)) {
                    ModuleShortcutCard(title: entry.0.title, systemImage: entry.1)
                }.buttonStyle(.plain)
                }
            }
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
    var body: some View {
        Group {
            if needsLogin {
                ScrollView {
                    ContentUnavailableView {
                        Label("登录网易云音乐", systemImage: "person.crop.circle")
                    } description: { Text("登录后查看\(route.title)。") } actions: {
                        Button("登录") { store.showsLogin = true }.buttonStyle(.borderedProminent)
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
                                if supportsFavorite {
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
                        if route == .liked {
                            NeteaseHeartModeButton().padding(.horizontal, 20).padding(.bottom, 16)
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
                        if route == .myPlaylists { NeteaseLibraryLinks() }
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
            if supportsFavorite, let sourceID, model.hasLoaded {
                ToolbarItem(placement: .topBarTrailing) {
                    NeteaseDownloadButton(kind: model.playlist == nil ? "album" : "playlist", id: sourceID,
                                          title: model.title, coverURL: artwork)
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
    @Environment(PlayerStore.self) private var player
    @Environment(NeteaseStore.self) private var store
    @Environment(\.openRoute) private var openRoute
    @Environment(DownloadStore.self) private var downloads
    @Environment(OfflineLibraryStore.self) private var library
    @State private var downloadedKeys: Set<RemoteTrackKey> = []
    @State private var showsDownloads = false
    @State private var addingSong: NeteaseSong?
    @State private var error: String?
    var body: some View {
        LazyVStack(spacing: 0) {
            ForEach(Array(songs.enumerated()), id: \.element.id) { index, song in
                AlbumTrackRow(track: song.track, displayNumber: String(index + 1), isDownloaded: song.track.remoteKey.map(downloadedKeys.contains) == true, additionalActions: actions(song)) {
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
        .sheet(item: $addingSong) { song in NeteasePlaylistPicker(songID: song.id) }
        .alert("操作失败", isPresented: Binding(get: { error != nil }, set: { if !$0 { error = nil } })) {
            Button("好", role: .cancel) { error = nil }
        } message: { Text(error ?? "") }
    }
    private func actions(_ song: NeteaseSong) -> [AlbumRowAction] {
        let liked = store.library.likedIDs.contains(song.id)
        var actions: [AlbumRowAction] = [
            .init(id: "like", title: liked ? "取消喜欢" : "喜欢", systemImage: liked ? "heart.fill" : "heart",
                  disabled: store.library.pending.contains("song/\(song.id)")) {
                guard store.profile != nil else { store.showsLogin = true; return }
                Task {
                    do { try await store.library.toggleLike(song.id) }
                    catch is CancellationError { }
                    catch { self.error = error.localizedDescription }
                }
            },
            .init(id: "add", title: "加入歌单", systemImage: "text.badge.plus") {
                if store.profile == nil { store.showsLogin = true } else { addingSong = song }
            },
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
        else if model.more { Button("加载更多") { Task { await retry() } }.frame(maxWidth: .infinity).buttonStyle(.bordered) }
        else if model.isEmpty && model.error == nil {
            Text("这里还没有内容。")
                .font(.subheadline).foregroundStyle(DizzyPalette.mutedText)
                .frame(maxWidth: .infinity).padding(.vertical, 60)
        }
    }
}
