import Foundation

#if os(iOS)
/// 导出、导入与自动备份共用的资料库和设置来源。
@MainActor struct LibraryContext {
    let favorites: FavoritesStore
    let mirror: AccountLibraryMirror
    let saved: SavedLibraryStore
    let offline: OfflineLibraryStore
    let providers: LibraryProviderRegistry
    let modules: ModuleSettings
    let downloads: DownloadStore
    var appearance: AppearanceSettings = .shared
    var defaults: UserDefaults = .standard

    func snapshot() -> LibraryExport {
        LibraryExport.snapshot(favorites: favorites, mirror: mirror, saved: saved, offline: offline, settings: settings())
    }

    func settings() -> LibraryExport.Settings {
        LibraryExport.Settings(appearance: appearance.mode.rawValue,
                               immersive: defaults.bool(forKey: ImmersiveMode.storageKey),
                               moduleOrder: modules.order.map(\.rawValue), hiddenModules: modules.hidden.map(\.rawValue).sorted(),
                               startupModule: modules.startupModule.rawValue, searchOrder: modules.searchOrder.map(\.rawValue),
                               providerSettings: providers.settings(),
                               concurrentDownloads: downloads.concurrentDownloadCount,
                               lyricsFocusPosition: defaults.object(forKey: LyricsFocus.storageKey) as? Double)
    }

    /// 只改文件里写了的项；无法识别的值保持当前设置。旧备份里的主题色已不再使用，忽略。
    func apply(_ settings: LibraryExport.Settings) {
        if let mode = settings.appearance.flatMap(AppAppearance.init(rawValue:)) { appearance.mode = mode }
        if let immersive = settings.immersive { defaults.set(immersive, forKey: ImmersiveMode.storageKey) }
        if let order = settings.moduleOrder {
            modules.restore(order: order.map { ModuleID(rawValue: $0) },
                            hidden: Set((settings.hiddenModules ?? []).map { ModuleID(rawValue: $0) }),
                            startup: settings.startupModule.map { ModuleID(rawValue: $0) } ?? modules.startupModule,
                            search: (settings.searchOrder ?? []).map { ModuleID(rawValue: $0) })
        }
        var values = settings.providerSettings ?? [:]
        if let legacy = settings.neteaseQuality, values["netease"] == nil { values["netease"] = ["quality": legacy] }
        providers.apply(values)
        if let count = settings.concurrentDownloads { downloads.concurrentDownloadCount = count }
        if let position = settings.lyricsFocusPosition { defaults.set(min(1, max(0, position)), forKey: LyricsFocus.storageKey) }
    }

    /// 已注册平台愿意备份的当前会话；没登录时为空。
    func credentials() -> LibraryExport.Credentials? {
        let values = providers.credentials()
        return values.isEmpty ? nil : LibraryExport.Credentials(providers: values)
    }

    /// 合并进现有资料库，不删除任何已有内容。
    /// 平台的喜欢、歌单和收藏随账号同步，登录后自动回来，这里不写入账号。
    func restore(_ export: LibraryExport, includeSettings: Bool) async throws -> LibraryRestoreReport {
        // 下载歌单的文件不在「专辑」里显示，但喜欢也可能落在它们身上，所以对照全部本地曲目。
        var report = try Self.restoreLibrary(export, favorites: favorites, saved: saved, localTracks: offline.localAlbums.flatMap(\.tracks))
        if includeSettings, let settings = export.settings { apply(settings); report.settingsApplied = true }
        var credentials = export.credentials?.providers ?? [:]
        if let legacy = export.credentials?.neteaseCookie, credentials["netease"] == nil { credentials["netease"] = legacy }
        report.accounts = await providers.restore(credentials)
        return report
    }

    /// 本地歌曲的喜欢先按文件身份、再按标题、歌手和专辑对回当前音乐库里的文件（重装后文件身份会变）。
    /// 对不上的记在 `FavoritesStore.unmatchedLocal`，之后的备份照样带着，下次导入再试。
    static func restoreLibrary(_ export: LibraryExport, favorites: FavoritesStore, saved: SavedLibraryStore,
                               localTracks: [Track]) throws -> LibraryRestoreReport {
        var report = LibraryRestoreReport()
        let byID = Dictionary(localTracks.map { (LibraryExport.Song.portableID(FavoriteSong(track: $0).itemID), $0) }, uniquingKeysWith: { first, _ in first })
        let byFullKey = Dictionary(localTracks.map { (Self.matchKey($0.title, $0.artists, $0.albumTitle), $0) }, uniquingKeysWith: { first, _ in first })
        let byTitle = Dictionary(localTracks.map { (Self.matchKey($0.title, $0.artists, nil), $0) }, uniquingKeysWith: { first, _ in first })

        var deviceSongs: [FavoriteSong] = []
        var accountSongs: [FavoriteSong] = []
        var unmatched: [FavoriteSong] = []
        let pending = favorites.unmatchedLocal.map { LibraryExport.Song($0.track, addedAt: $0.addedAt) }
        for song in export.favorites + pending {
            switch song.providerID {
            case "local":
                guard let track = byID[song.itemID] ?? byFullKey[Self.matchKey(song.title, song.artists, song.albumTitle)]
                        ?? byTitle[Self.matchKey(song.title, song.artists, nil)] else {
                    unmatched.append(FavoriteSong(track: Self.localTrack(song), addedAt: song.addedAt)); continue
                }
                deviceSongs.append(FavoriteSong(track: track, addedAt: song.addedAt))
            case "dizzylab":
                deviceSongs.append(FavoriteSong(track: Self.track(song, remote: false), addedAt: song.addedAt))
            default:
                // 账号喜欢登录后自动同步回来，这里只恢复它们的喜欢时间，免得同步后全部排在最前。
                accountSongs.append(FavoriteSong(track: Self.track(song, remote: true), addedAt: song.addedAt))
                report.accountFavorites += 1
            }
        }
        // 早期版本把 DizzyLab 的歌记成「收藏」，现在它们就是喜欢；放回收藏不会再被迁移，会从「喜欢」里消失。
        for song in export.savedSongs where song.providerID == "dizzylab" {
            deviceSongs.append(FavoriteSong(track: Self.track(song, remote: false), addedAt: song.addedAt))
        }
        report.favoritesAdded = try favorites.importDeviceSongs(deviceSongs)
        try favorites.restoreAccountTimes(accountSongs)
        var seen = Set<String>()
        let stillUnmatched = unmatched.filter { seen.insert($0.id).inserted }
        try favorites.setUnmatchedLocal(stillUnmatched)
        report.unmatchedLocal = stillUnmatched.count

        for song in export.savedSongs where song.providerID != "local" && song.providerID != "dizzylab" {
            let item = SavedLibraryItem.song(Self.track(song, remote: song.providerID != "dizzylab"), providerID: song.providerID,
                                             itemID: song.itemID, addedAt: song.addedAt ?? .now)
            if !saved.contains(.song, providerID: item.providerID, itemID: item.itemID) { guard saved.add(item) else { throw CocoaError(.fileWriteUnknown) }; report.savedAdded += 1 }
        }
        for collection in export.collections {
            guard collection.origin != .local, collection.origin != .account, collection.providerID != "local",
                  let kind = SavedLibraryItem.Kind(rawValue: collection.kind), kind != .song else { continue }
            // 账号里的网易云收藏登录后自动同步；只在 App 里手动加入、还没提交到账号的（.saved）要放回本机，
            // 登录后会像以前一样提交到账号。旧版文件分不清来源，按账号内容处理。
            if collection.providerID == "netease", collection.origin != .saved { report.accountCollections += 1; continue }
            guard !saved.contains(kind, providerID: collection.providerID, itemID: collection.itemID) else { continue }
            guard saved.add(SavedLibraryItem(kind: kind, providerID: collection.providerID, itemID: collection.itemID, title: collection.title,
                                       subtitle: collection.subtitle, coverURL: collection.coverURL, track: nil, addedAt: .now)) else { throw CocoaError(.fileWriteUnknown) }
            report.savedAdded += 1
        }
        return report
    }

    static func matchKey(_ title: String, _ artists: String, _ album: String?) -> String {
        [title, artists, album ?? ""].map { $0.trimmingCharacters(in: .whitespaces).lowercased() }.joined(separator: "\u{1F}")
    }

    /// 找不到文件的本地喜欢：保留导出时的文件身份和标题，供之后的备份和导入使用。
    static func localTrack(_ song: LibraryExport.Song) -> Track {
        Track(discID: "", number: song.number, title: song.title, artists: song.artists, albumTitle: song.albumTitle,
              coverURL: nil, duration: song.duration, localSource: LocalTrackSource(albumID: song.albumID, trackID: song.itemID))
    }

    /// DizzyLab 曲目的身份就是「专辑 ID/序号」；其他平台用显式的 remoteSource。
    static func track(_ song: LibraryExport.Song, remote: Bool) -> Track {
        Track(discID: song.albumID, number: song.number, title: song.title, artists: song.artists, albumTitle: song.albumTitle,
              coverURL: song.coverURL, duration: song.duration,
              remoteSource: remote ? RemoteTrackSource(providerID: song.providerID, itemID: song.itemID) : nil)
    }
}

#endif

struct LibraryRestoreReport: Equatable {
    var favoritesAdded = 0
    var savedAdded = 0
    var unmatchedLocal = 0
    var accountFavorites = 0
    var accountCollections = 0
    var settingsApplied = false
    enum Login: Equatable { case restored, alreadySignedIn, expired }
    struct Account: Equatable { let title: String; let status: Login }
    var accounts: [String: Account] = [:]

    var lines: [String] {
        var lines = ["新增 \(favoritesAdded) 首喜欢，\(savedAdded) 个收藏。"]
        if settingsApplied { lines.append("已恢复外观、主题、模块顺序等设置。") }
        for id in accounts.keys.sorted() {
            guard let account = accounts[id] else { continue }
            switch account.status {
            case .restored: lines.append("已恢复\(account.title)登录，账号内容会自动同步回来。")
            case .alreadySignedIn: lines.append("\(account.title)已登录，保留当前账号。")
            case .expired: lines.append("备份里的\(account.title)登录已过期，请重新登录。")
            }
        }
        if accountFavorites + accountCollections > 0 {
            lines.append("\(accountFavorites) 首平台喜欢和 \(accountCollections) 个平台播放列表、专辑随账号保存，启用对应模块并登录后自动同步。")
        }
        if unmatchedLocal > 0 {
            lines.append("\(unmatchedLocal) 首本地歌曲的喜欢暂未恢复：音乐库里找不到同名文件。它们会继续记在备份里，把音乐放回「文件 › 我的 iPhone › NeoDizzy」后再导入一次即可。")
        }
        return lines
    }
}

/// 歌词定位的设置项，歌词页与设置页共用。
enum LyricsFocus {
    static let storageKey = "lyrics.focusPosition"
}
