import Foundation
import Observation

/// 资料库里来自平台账号的专辑或歌单。
nonisolated struct MirroredCollection: Codable, Hashable, Identifiable, Sendable {
    enum Kind: String, Codable, Sendable { case album, playlist }

    let providerID: String
    let kind: Kind
    let itemID: String
    let title: String
    let subtitle: String
    let coverURL: URL?
    /// 网易云账号自带的「我喜欢的音乐」。
    var isLikedPlaylist = false
    /// 自己创建的歌单或已购专辑：不能从账号里取消，只能在平台上管理。
    var isPermanent = false
    /// 第一次同步到这一项的时间，用于「最近添加」。
    var firstSeen: Date

    var id: String { "\(providerID)/\(kind.rawValue)/\(itemID)" }
}

/// 网易云与 DizzyLab 账号内容的本机镜像：只在启动、回到前台、下拉刷新和账号操作后同步，
/// 同步结果写进 App 支持目录，离线时资料库照样能看。
@Observable
@MainActor
final class AccountLibraryMirror {
    private struct Snapshot: Codable {
        var neteaseUserID: Int?
        // 仅用于迁移旧版喜欢缓存，新喜欢状态存入 favorites.sqlite。
        var likedTracks: [Int: Track] = [:]
        var likedOrder: [Int] = []
        var neteaseCollections: [MirroredCollection] = []
        var dizzyLabUserID: Int?
        var dizzyLabAlbums: [MirroredCollection] = []
        var firstSeen: [String: Date] = [:]
        /// 歌手名 → 网易云歌手 ID，来自喜欢的歌的详情。
        var artistIDs: [String: Int] = [:]
        var artistAvatars: [Int: URL] = [:]
    }

    private var snapshot = Snapshot()
    private(set) var isSyncing = false
    @ObservationIgnored private let fileURL: URL
    @ObservationIgnored private var neteaseSync: Task<Void, Error>?
    @ObservationIgnored private var dizzyLabSync: Task<Void, Error>?
    @ObservationIgnored private var avatarRequests = Set<Int>()
    @ObservationIgnored private var neteaseGeneration = 0
    @ObservationIgnored private var dizzyLabGeneration = 0
    @ObservationIgnored private let loadPurchases: (Int, Int) async throws -> Page<PurchasedDisc>

    init(directory: URL = URL.applicationSupportDirectory.appendingPathComponent("Library", isDirectory: true),
         loadPurchases: @escaping (Int, Int) async throws -> Page<PurchasedDisc> = { userID, page in
             try await DizzyPages.shared.purchases(userID: userID, page: page)
         }) {
        self.loadPurchases = loadPurchases
        fileURL = directory.appendingPathComponent("account-mirror.json")
        if let data = try? Data(contentsOf: fileURL), let saved = try? JSONDecoder().decode(Snapshot.self, from: data) {
            snapshot = saved
        }
    }

    // MARK: Reading

    /// 网易云「喜欢」的歌，按喜欢的先后从新到旧。
    var neteaseAccountID: Int? { snapshot.neteaseUserID }
    var neteaseLikedTracks: [Track] { snapshot.likedOrder.compactMap { snapshot.likedTracks[$0] } }
    var neteaseCollections: [MirroredCollection] { snapshot.neteaseCollections }
    var dizzyLabAlbums: [MirroredCollection] { snapshot.dizzyLabAlbums }

    // MARK: NetEase

    /// 本机账号操作后重建专辑和歌单镜像；喜欢列表由 FavoritesStore 管理。
    func rebuildNetease(from store: NeteaseStore) {
        let library = store.library
        rebuildNetease(from: library)
    }

    /// 只用内存里的账号数据重建，不发请求。
    func rebuildNetease(from library: NeteaseLibrary) {
        guard library.userID == snapshot.neteaseUserID, library.userID != nil else { return }
        if library.playlistsLoaded || library.albumsLoaded {
            let updated = collections(from: library)
            let playlists = library.playlistsLoaded ? updated.filter { $0.kind == .playlist }
                : snapshot.neteaseCollections.filter { $0.kind == .playlist }
            let albums = library.albumsLoaded ? updated.filter { $0.kind == .album }
                : snapshot.neteaseCollections.filter { $0.kind == .album }
            snapshot.neteaseCollections = playlists + albums
        }
        save()
    }

    /// 从网易云拉一次歌单和收藏的专辑。`force` 时忽略已加载的数据。
    func syncNetease(_ store: NeteaseStore, force: Bool) async throws {
        let userID = store.profile?.userId
        if snapshot.neteaseUserID != userID {
            neteaseGeneration += 1
            neteaseSync?.cancel()
            neteaseSync = nil
            isSyncing = false
            snapshot.neteaseUserID = userID
            snapshot.likedTracks = [:]; snapshot.likedOrder = []; snapshot.neteaseCollections = []
            save()
        }
        guard userID != nil else { return }
        if let neteaseSync { return try await neteaseSync.value }
        let generation = neteaseGeneration
        let task = Task { try await performNeteaseSync(store, force: force, generation: generation) }
        neteaseSync = task
        defer { if generation == neteaseGeneration { neteaseSync = nil } }
        try await task.value
    }

    private func performNeteaseSync(_ store: NeteaseStore, force: Bool, generation: Int) async throws {
        try Task.checkCancellation()
        guard generation == neteaseGeneration else { throw CancellationError() }
        isSyncing = true
        defer { if generation == neteaseGeneration { isSyncing = false } }
        let library = store.library
        var failure: Error?
        do {
            try await library.loadPlaylists(force: force)
            try Task.checkCancellation()
            guard generation == neteaseGeneration else { throw CancellationError() }
            rebuildNetease(from: library)
        } catch { failure = error }
        try Task.checkCancellation()
        guard generation == neteaseGeneration else { throw CancellationError() }
        do {
            try await library.loadAlbums(force: force)
            try Task.checkCancellation()
            guard generation == neteaseGeneration else { throw CancellationError() }
            rebuildNetease(from: library)
        } catch { failure = error }
        if let failure { throw failure }
    }

    func recordFavoriteMetadata(_ songs: [NeteaseSong]) {
        record(songs)
        save()
    }

    private func record(_ songs: [NeteaseSong]) {
        for song in songs {
            for artist in song.artists where artist.id > 0 { snapshot.artistIDs[artist.name] = artist.id }
        }
    }

    // MARK: Artists

    func neteaseArtistID(named name: String) -> Int? { snapshot.artistIDs[name] }
    func artistAvatar(_ id: Int) -> URL? { snapshot.artistAvatars[id] }

    /// 进入歌手列表时按需读取网易云歌手头像，读到后存进本机镜像，之后不再请求。
    func loadArtistAvatar(_ id: Int, api: NeteaseAPI) async {
        guard snapshot.artistAvatars[id] == nil, avatarRequests.insert(id).inserted else { return }
        defer { avatarRequests.remove(id) }
        guard let url = try? await api.artist(id).artist.artworkURL else { return }
        snapshot.artistAvatars[id] = url
        save()
    }

    private func collections(from library: NeteaseLibrary) -> [MirroredCollection] {
        let playlists = library.playlists.map { playlist in
            let own = playlist.creator?.userId == library.userID
            let liked = own && playlist.specialType == 5
            let subtitle = liked ? String(localized: "网易云 · \(playlist.trackCount ?? 0) 首")
                : own ? String(localized: "我创建的 · \(playlist.trackCount ?? 0) 首")
                : String(localized: "收藏 · \(playlist.creator?.nickname ?? "网易云")")
            return item(providerID: "netease", kind: .playlist, itemID: String(playlist.id),
                        title: liked ? String(localized: "我喜欢的音乐") : playlist.name, subtitle: subtitle,
                        coverURL: playlist.artworkURL, isLikedPlaylist: liked, isPermanent: own)
        }
        // 「我喜欢的音乐」永远排在最前。
        let ordered = playlists.filter(\.isLikedPlaylist) + playlists.filter { !$0.isLikedPlaylist }
        let albums = library.albums.map { album in
            item(providerID: "netease", kind: .album, itemID: String(album.id), title: album.name,
                 subtitle: album.artist?.name ?? String(localized: "网易云"), coverURL: album.artworkURL)
        }
        return ordered + albums
    }

    // MARK: DizzyLab

    /// 拉取 DizzyLab 已购专辑（公开页面，一页一页翻）。
    func syncDizzyLab(userID: Int?) async throws {
        if snapshot.dizzyLabUserID != userID {
            dizzyLabGeneration += 1
            dizzyLabSync?.cancel()
            dizzyLabSync = nil
            snapshot.dizzyLabUserID = userID
            snapshot.dizzyLabAlbums = []
            save()
        }
        guard let userID else { return }
        if let dizzyLabSync { return try await dizzyLabSync.value }
        let generation = dizzyLabGeneration
        let task = Task { try await performDizzyLabSync(userID: userID, generation: generation) }
        dizzyLabSync = task
        defer { if generation == dizzyLabGeneration { dizzyLabSync = nil } }
        try await task.value
    }

    private func performDizzyLabSync(userID: Int, generation: Int) async throws {
        try Task.checkCancellation()
        guard generation == dizzyLabGeneration else { throw CancellationError() }
        var discs: [PurchasedDisc] = []
        var page = 1
        while page <= 50 {
            let result = try await loadPurchases(userID, page)
            try Task.checkCancellation()
            guard generation == dizzyLabGeneration else { throw CancellationError() }
            discs += result.items
            guard result.hasMore, !result.items.isEmpty else { break }
            page += 1
        }
        var seen = Set<String>()
        snapshot.dizzyLabUserID = userID
        snapshot.dizzyLabAlbums = discs.filter { seen.insert($0.id).inserted }.map { purchased in
            item(providerID: "dizzylab", kind: .album, itemID: purchased.disc.id, title: purchased.disc.title,
                 subtitle: purchased.disc.labelName ?? "DizzyLab", coverURL: purchased.disc.coverURL, isPermanent: true)
        }
        save()
    }

    func isDizzyLabAlbumPurchased(_ id: String) -> Bool { snapshot.dizzyLabAlbums.contains { $0.itemID == id } }

    // MARK: Storage

    private func item(providerID: String, kind: MirroredCollection.Kind, itemID: String, title: String, subtitle: String,
                      coverURL: URL?, isLikedPlaylist: Bool = false, isPermanent: Bool = false) -> MirroredCollection {
        let key = "\(providerID)/\(kind.rawValue)/\(itemID)"
        let firstSeen = snapshot.firstSeen[key] ?? .now
        snapshot.firstSeen[key] = firstSeen
        return MirroredCollection(providerID: providerID, kind: kind, itemID: itemID, title: title, subtitle: subtitle,
                                  coverURL: coverURL, isLikedPlaylist: isLikedPlaylist, isPermanent: isPermanent, firstSeen: firstSeen)
    }

    private func save() {
        do {
            try FileManager.default.createDirectory(at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
            try JSONEncoder().encode(snapshot).write(to: fileURL, options: .atomic)
        } catch {
            assertionFailure("Saving the account library mirror failed: \(error)")
        }
    }
}

/// 多人署名按逗号、斜杠和顿号拆开。
nonisolated enum LibraryArtistNames {
    static func split(_ artists: String) -> [String] {
        artists.split(whereSeparator: { ",，/、".contains($0) })
            .map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
    }
}
