import Foundation

/// 可移植的资料库清单；只导出明确列出的元数据，不序列化音频地址或沙盒路径。
/// 第 2 版加入设置、封面、集合来源和（仅本机备份的）登录凭据；导入时仍接受第 1 版文件。
nonisolated struct LibraryExport: Codable {
    static let formatName = "NeoDizzyLibrary"
    var format = Self.formatName
    var version = 2
    let exportedAt: Date
    var favorites: [Song]
    var savedSongs: [Song]
    var collections: [Collection]
    var settings: Settings?
    /// 只写进 App 自己文件夹里的备份；分享出去的配置文件不带登录凭据。
    var credentials: Credentials?

    struct Song: Codable {
        let providerID: String
        let itemID: String
        let title: String
        let artists: String
        let albumTitle: String
        let albumID: String
        let number: String
        let duration: Double?
        let addedAt: Date?
        /// 只保留不带查询参数的网络封面，避免带出签名或令牌。
        var coverURL: URL?
        init(_ track: Track, addedAt: Date? = nil) {
            let identity = FavoriteSong(track: track)
            providerID = identity.providerID
            itemID = Self.portableID(identity.itemID)
            title = track.title; artists = track.artists; albumTitle = track.albumTitle
            albumID = Self.portableID(track.discID); number = track.number
            duration = track.duration; self.addedAt = addedAt
            coverURL = Self.portableCover(track.coverURL)
        }
        static func portableID(_ id: String) -> String {
            id.hasPrefix("/") || id.hasPrefix("file:") ? URL(fileURLWithPath: id).lastPathComponent : id
        }
        static func portableCover(_ url: URL?) -> URL? {
            guard let url, ["http", "https"].contains(url.scheme?.lowercased() ?? ""), url.query == nil else { return nil }
            return url
        }
    }
    struct Collection: Codable {
        enum Origin: String, Codable { case local, account, saved }
        let providerID: String
        let kind: String
        let itemID: String
        let title: String
        let subtitle: String
        var songs: [Song]
        /// 未能拉取完整列表时保留条目，并明确说明缺失，不能把空数组伪装成空歌单。
        var songsComplete: Bool
        var issue: String?
        /// 本地文件、账号同步或手动加入；第 1 版文件没有这一项。
        var origin: Origin?
        var coverURL: URL?
    }

    /// 外观、导航和播放设置。全部可选：旧文件或新版本删掉的设置不影响导入其余部分。
    struct Settings: Codable, Equatable {
        var theme: String?
        var appearance: String?
        var immersive: Bool?
        var moduleOrder: [String]?
        var hiddenModules: [String]?
        var startupModule: String?
        var searchOrder: [String]?
        var neteaseQuality: String?
        var concurrentDownloads: Int?
        var lyricsFocusPosition: Double?
    }

    struct Credentials: Codable, Equatable {
        /// 网易云会话 Cookie（含 MUSIC_U），与钥匙串里保存的完全相同。
        var neteaseCookie: String?
    }

    func data() throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        encoder.dateEncodingStrategy = .iso8601
        return try encoder.encode(self)
    }

    static func decode(_ data: Data) throws -> LibraryExport {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        guard let export = try? decoder.decode(LibraryExport.self, from: data), export.format == formatName else {
            throw ImportError.notLibraryFile
        }
        guard export.version <= 2 else { throw ImportError.newerVersion }
        return export
    }

    enum ImportError: LocalizedError {
        case notLibraryFile, newerVersion
        var errorDescription: String? {
            switch self {
            case .notLibraryFile: "这不是 NeoDizzy 导出的资料库配置文件。"
            case .newerVersion: "这个配置文件来自更新版本的 NeoDizzy，请先更新 App。"
            }
        }
    }

    @MainActor static func snapshot(favorites: FavoritesStore, mirror: AccountLibraryMirror,
                                   saved: SavedLibraryStore, offline: OfflineLibraryStore,
                                   settings: Settings? = nil) -> LibraryExport {
        let localAlbums = offline.visibleAlbums.map { album in
            Collection(providerID: "local", kind: "album", itemID: Song.portableID(album.id), title: album.title,
                       subtitle: album.artist, songs: album.tracks.map { Song($0) }, songsComplete: true, origin: .local)
        }
        let localPlaylists = offline.localPlaylists.map { playlist in
            Collection(providerID: playlist.source?.provider ?? "local", kind: "localPlaylist",
                       itemID: playlist.source?.id ?? playlist.fileURL.lastPathComponent, title: playlist.title,
                       subtitle: "本地歌单", songs: playlist.tracks.map { Song($0) }, songsComplete: true, origin: .local)
        }
        let remote = (mirror.neteaseCollections + mirror.dizzyLabAlbums).filter { !$0.isLikedPlaylist }.map { item in
            Collection(providerID: item.providerID, kind: item.kind.rawValue, itemID: item.itemID,
                       title: item.title, subtitle: item.subtitle, songs: [], songsComplete: false, origin: .account,
                       coverURL: Song.portableCover(item.coverURL))
        }
        let keys = Set(remote.map { "\($0.providerID)/\($0.kind)/\($0.itemID)" })
        let manual = saved.items.filter { $0.kind != .song && !keys.contains("\($0.providerID)/\($0.kind.rawValue)/\($0.itemID)") }.map { item in
            Collection(providerID: item.providerID, kind: item.kind.rawValue, itemID: item.itemID,
                       title: item.title, subtitle: item.subtitle, songs: [], songsComplete: false, origin: .saved,
                       coverURL: Song.portableCover(item.coverURL))
        }
        // 上次导入没对上文件的本地喜欢也写进去，否则自动备份覆盖旧文件后就永久丢了。
        var seen = Set<String>()
        let liked = (favorites.songs + favorites.unmatchedLocal).filter { seen.insert($0.id).inserted }
        return LibraryExport(exportedAt: .now, favorites: liked.map { Song($0.track, addedAt: $0.addedAt) },
                             savedSongs: saved.items.compactMap { item in item.track.map { Song($0, addedAt: item.addedAt) } },
                             collections: localAlbums + localPlaylists + remote + manual, settings: settings)
    }

    /// 逐个补齐在线集合；单项失败不会丢掉其他集合，文件内标记不完整项。
    @MainActor mutating func loadOnlineSongs(netease: NeteaseStore, progress: (Int, Int) -> Void) async throws {
        let revision = netease.revision
        let indices = collections.indices.filter { !collections[$0].songsComplete }
        for (position, index) in indices.enumerated() {
            try Task.checkCancellation()
            guard netease.revision == revision else { throw CancellationError() }
            progress(position + 1, indices.count)
            let item = collections[index]
            do {
                let tracks: [Track]
                if item.providerID == "netease", let id = Int(item.itemID) {
                    if item.kind == "playlist" {
                        let playlist = try await netease.api.playlist(id)
                        let ids = playlist.trackIds?.map(\.id) ?? playlist.tracks?.map(\.id) ?? []
                        guard !ids.isEmpty || (playlist.trackCount ?? 0) == 0 else { throw NeteaseError.emptyResponse }
                        var songs: [NeteaseSong] = []
                        for start in stride(from: 0, to: ids.count, by: 400) {
                            try Task.checkCancellation()
                            songs += try await netease.api.songs(Array(ids[start..<min(start + 400, ids.count)]))
                        }
                        guard songs.count == ids.count else { throw NeteaseError.emptyResponse }
                        tracks = songs.map(\.track)
                    } else { tracks = try await netease.api.album(id).1.map(\.track) }
                } else if item.providerID == "dizzylab", item.kind == "album" {
                    tracks = try await DizzyAPI.shared.discDetail(id: item.itemID).tracks
                } else { throw NeteaseError.response }
                guard netease.revision == revision else { throw CancellationError() }
                collections[index].songs = tracks.map { Song($0) }
                collections[index].songsComplete = true
            } catch is CancellationError { throw CancellationError() }
            catch { collections[index].issue = "未能读取完整歌曲列表，请联网后重新导出。" }
        }
    }
}
