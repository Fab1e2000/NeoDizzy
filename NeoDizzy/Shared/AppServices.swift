import Foundation

/// 由 AppDelegate 持有一次，后台唤醒时也能恢复下载，不依赖某个页面出现。iOS 与 macOS 共用。
final class AppServices {
    let neteaseDownloads: NeteaseDownloadProvider
    let netease: NeteaseStore
    let dizzyLab: DizzyLabServices
    var browsingHistory: BrowsingHistoryStore { dizzyLab.browsingHistory }
    var account: AccountStore { dizzyLab.account }
    let offlineLibrary: OfflineLibraryStore
    var downloads: DownloadStore { dizzyLab.downloads }
    var purchases: PurchaseStore { dizzyLab.purchases }
    let player: PlayerStore
    /// 手动加入资料库的在线歌曲、专辑和歌单。
    let savedLibrary = SavedLibraryStore()
    let favorites = FavoritesStore()
    /// 网易云喜欢、歌单、收藏专辑与 DizzyLab 已购专辑在资料库里的镜像。
    let accountLibrary = AccountLibraryMirror()
    /// 资料库「最近播放」的专辑记录。
    let playbackHistory = PlaybackHistoryStore()

    init() {
        favorites.migrateSavedSongs(from: savedLibrary)
        #if os(iOS)
        // 「文件 › 我的 iPhone › NeoDizzy」就是 App 的 Documents 文件夹，下载和导入都存在这里。
        // 「文件」App 不显示空的 App 文件夹，先建好两个平台的下载文件夹，让它一直能被找到。
        for provider in ["netease", "dizzylab"] {
            try? FileManager.default.createDirectory(at: URL.documentsDirectory.appending(path: provider, directoryHint: .isDirectory),
                                                     withIntermediateDirectories: true)
        }
        let library = OfflineLibraryStore(libraryRoot: .documentsDirectory)
        #else
        let library = OfflineLibraryStore()
        #endif
        offlineLibrary = library
        dizzyLab = DizzyLabServices(library: library)
        netease = NeteaseStore()
        neteaseDownloads = NeteaseDownloadProvider(api: netease.api, library: library)
        neteaseDownloads.playlistCompleted = { [weak library] title, id, tracks in
            guard let library else { return }
            try await library.savePlaylist(title: title, tracks: tracks,
                                           source: LibrarySource(provider: "netease", kind: "playlist", id: id))
        }
        dizzyLab.downloads.register(neteaseDownloads)
        let qualitySettings = netease.playbackSettings
        let apiQuality = { qualitySettings.selected.rawValue }
        let resolver = StreamResolver(localFile: { [weak library] track in
            library?.localFile(for: track, quality: track.remoteSource?.providerID == "netease" ? apiQuality() : nil)
        }, localAccess: { [weak library] track in
            library?.access(for: track, quality: track.remoteSource?.providerID == "netease" ? apiQuality() : nil)
        })
        let likesStore = netease
        let accountMirror = accountLibrary
        if let account = accountMirror.neteaseAccountID {
            favorites.migrate(providerID: "netease", account: String(account), tracks: accountMirror.neteaseLikedTracks)
        }
        favorites.register("netease", provider: FavoritesProvider(
            account: { likesStore.profile.map { String($0.userId) } },
            load: {
                let revision = likesStore.revision
                guard let userID = likesStore.profile?.userId else { throw NeteaseError.loginRequired }
                let songs = try await likesStore.api.favoritePlaylistSongs(userID: userID)
                guard likesStore.revision == revision else { throw CancellationError() }
                accountMirror.recordFavoriteMetadata(songs)
                return songs.map(\.track)
            },
            setLiked: { track, liked in
                guard let id = (track.remoteSource?.itemID).flatMap(Int.init) else { throw NeteaseError.response }
                try await likesStore.library.setSongLiked(id, liked)
            }))
        let api = netease.api
        resolver.register("netease", stream: { try await api.stream($0) }, lyrics: { try await api.lyrics($0) }, cacheKey: { api.cacheKey(for: $0.id) })
        player = PlayerStore(resolver: resolver)
        let reporter = netease.reporter
        let history = playbackHistory
        player.reporting.onStart = { [weak reporter, weak history] track, source in
            reporter?.started(track, sourceID: source)
            Task { @MainActor in history?.record(track) }
        }
        player.reporting.onFinish = { [weak reporter] track, source, seconds in reporter?.finished(track, sourceID: source, seconds: seconds) }
        netease.playbackSettings.changed = { [weak player] in player?.remoteQualityDidChange(providerID: "netease") }
        let radio = netease.radio
        player.registerDiscovery("netease") { try await radio.next() }
        netease.accountChanged = { [weak player] in player?.remoteAccountDidChange(providerID: "netease") }
    }

    /// 把网易云与 DizzyLab 账号内容同步进资料库；失败时保留上次的本机镜像。
    @MainActor func syncAccountLibrary(force: Bool) async {
        let mirror = accountLibrary, store = netease, userID = account.account?.userID
        async let favoritesDone: Void = favorites.refresh()
        async let neteaseDone: Void = { try? await mirror.syncNetease(store, force: force) }()
        async let dizzyLabDone: Void = { try? await mirror.syncDizzyLab(userID: userID) }()
        _ = await (neteaseDone, dizzyLabDone, favoritesDone)
        await migrateSavedNeteaseItems()
    }

    /// 早先只记在 App 里的网易云条目，换成账号里真正的喜欢与收藏，成功后删掉本机记录。
    @MainActor private func migrateSavedNeteaseItems() async {
        guard netease.profile != nil else { return }
        let library = netease.library
        for item in savedLibrary.items where item.providerID == "netease" {
            guard let id = Int(item.itemID) else { savedLibrary.remove(id: item.id); continue }
            do {
                switch item.kind {
                case .song:
                    let track: Track
                    if let saved = item.track { track = saved }
                    else {
                        guard let song = try await netease.api.songs([id]).first else { throw NeteaseError.emptyResponse }
                        track = song.track
                    }
                    try await favorites.setLiked(track, true)
                case .playlist:
                    let playlist = try await netease.api.playlist(id)
                    if library.isSubscribed(playlist) != true { try await library.togglePlaylist(playlist) }
                case .album:
                    try await library.loadAlbumStatus(id)
                    if library.albumStates[id] != true {
                        try await library.toggleAlbum(NeteaseAlbum(id: id, name: item.title, picUrl: nil, artist: nil))
                    }
                }
                savedLibrary.remove(id: item.id)
            } catch {
                continue
            }
        }
    }

    func restore() async {
        await offlineLibrary.restore()
        await dizzyLab.restore()
        player.restore()
    }
}
