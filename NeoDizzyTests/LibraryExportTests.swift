import Foundation
import Testing
@testable import NeoDizzy

@MainActor struct LibraryExportTests {
    @Test func exportPreservesOrderDuplicatesAndExplicitCompleteness() throws {
        func track(_ provider: String, _ number: String) -> Track {
            Track(discID: "album", number: number, title: "相同歌曲", artists: "作者", albumTitle: "专辑", coverURL: URL(string: "https://example.com/cover?token=secret"),
                  remoteSource: .init(providerID: provider, itemID: number))
        }
        let songs = [track("netease", "90"), track("qq", "90"), track("netease", "1")].map { LibraryExport.Song($0) }
        let export = LibraryExport(exportedAt: .now, favorites: songs, savedSongs: [], collections: [
            .init(providerID: "netease", kind: "playlist", itemID: "p", title: "歌单", subtitle: "", songs: [], songsComplete: false, issue: "未能读取")
        ])
        let data = try export.data()
        let restored = try LibraryExport.decode(data)
        #expect(restored.version == 2)
        #expect(restored.favorites.map(\.itemID) == ["90", "90", "1"])
        #expect(restored.favorites.map(\.providerID) == ["netease", "qq", "netease"])
        #expect(restored.collections.first?.songsComplete == false)
        #expect(!String(decoding: data, as: UTF8.self).contains("secret"))
    }

    @Test func exportExcludesSandboxPathsAndIncludesLocalMetadata() throws {
        let song = Track(discID: "/private/container/album", number: "2", title: "歌曲", artists: "歌手", albumTitle: "专辑", coverURL: URL(fileURLWithPath: "/private/container/cover.png"), duration: 123,
                         localSource: .init(albumID: "album", trackID: "/private/container/song.flac"))
        let export = LibraryExport(exportedAt: .now, favorites: [.init(song)], savedSongs: [], collections: [])
        let text = String(decoding: try export.data(), as: UTF8.self)
        #expect(!text.contains("/private/"))
        #expect(!text.contains("cover.png"))
        #expect(text.contains("song.flac"))
        #expect(text.contains("123"))
    }

    @Test func decodesVersionOneFilesAndRejectsOtherJSON() throws {
        let v1 = #"{"collections":[],"exportedAt":"2026-10-01T08:00:00Z","favorites":[],"format":"NeoDizzyLibrary","savedSongs":[],"version":1}"#
        let export = try LibraryExport.decode(Data(v1.utf8))
        #expect(export.version == 1)
        #expect(export.settings == nil)
        #expect(throws: LibraryExport.ImportError.self) { try LibraryExport.decode(Data(#"{"hello":1}"#.utf8)) }
        let future = v1.replacingOccurrences(of: #""version":1"#, with: #""version":9"#)
        #expect(throws: LibraryExport.ImportError.self) { try LibraryExport.decode(Data(future.utf8)) }
    }

    @Test func settingsRoundTrip() throws {
        let settings = LibraryExport.Settings(theme: "teal", appearance: "dark", immersive: true, moduleOrder: ["localLibrary", "dizzyLab"],
                                              hiddenModules: ["dizzyLab"], startupModule: "localLibrary", searchOrder: ["dizzyLab"],
                                              neteaseQuality: "lossless", concurrentDownloads: 4, lyricsFocusPosition: 0.3)
        let export = LibraryExport(exportedAt: .now, favorites: [], savedSongs: [], collections: [], settings: settings)
        #expect(try LibraryExport.decode(export.data()).settings == settings)
    }

    @Test func restoreMergesWithoutDuplicatesAndLeavesAccountContentToSync() throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: folder) }
        let favorites = FavoritesStore(directory: folder), saved = SavedLibraryStore(directory: folder)
        // 重装后本地文件身份改变，按标题、歌手和专辑对回来。
        let oldLocal = Track(discID: "", number: "1", title: "Local Song", artists: "Artist", albumTitle: "Album", coverURL: nil,
                             localSource: .init(albumID: "a", trackID: "old-id"))
        let newLocal = Track(discID: "", number: "1", title: "Local Song", artists: "Artist", albumTitle: "Album", coverURL: nil,
                             localSource: .init(albumID: "b", trackID: "new-id"))
        let dizzy = Track(discID: "disc9", number: "3", title: "Dizzy", artists: "Circle", albumTitle: "Disc", coverURL: URL(string: "https://img.example/c.jpg"))
        let netease = Track(discID: "1", number: "1", title: "云", artists: "歌手", albumTitle: "专辑", coverURL: nil, remoteSource: .init(providerID: "netease", itemID: "77"))
        let missing = Track(discID: "", number: "1", title: "Gone", artists: "X", albumTitle: "Y", coverURL: nil, localSource: .init(albumID: "a", trackID: "gone"))
        let export = LibraryExport(exportedAt: .now, favorites: [oldLocal, dizzy, netease, missing].map { LibraryExport.Song($0, addedAt: .now) },
                                   savedSongs: [LibraryExport.Song(netease)], collections: [
            .init(providerID: "dizzylab", kind: "album", itemID: "disc1", title: "手动专辑", subtitle: "社团", songs: [], songsComplete: false, origin: .saved),
            .init(providerID: "dizzylab", kind: "album", itemID: "disc2", title: "已购", subtitle: "社团", songs: [], songsComplete: false, origin: .account),
            .init(providerID: "netease", kind: "playlist", itemID: "5", title: "歌单", subtitle: "", songs: [], songsComplete: false),
            .init(providerID: "local", kind: "album", itemID: "a", title: "本地", subtitle: "", songs: [], songsComplete: true, origin: .local),
        ])

        let report = try LibraryContext.restoreLibrary(export, favorites: favorites, saved: saved, localTracks: [newLocal])
        #expect(report.favoritesAdded == 2)
        #expect(report.unmatchedLocal == 1)
        #expect(report.accountFavorites == 1)
        #expect(report.accountCollections == 1)
        #expect(Set(favorites.songs.map(\.id)) == ["local/new-id", "dizzylab/disc9/3"])
        #expect(favorites.contains(dizzy))
        #expect(saved.contains(.album, providerID: "dizzylab", itemID: "disc1"))
        #expect(!saved.contains(.album, providerID: "dizzylab", itemID: "disc2"))
        #expect(saved.contains(.song, providerID: "netease", itemID: "77"))
        #expect(saved.items(of: .song).first?.track?.remoteSource?.itemID == "77")

        // 再导入一次不重复。
        let again = try LibraryContext.restoreLibrary(export, favorites: favorites, saved: saved, localTracks: [newLocal])
        #expect(again.favoritesAdded == 0 && again.savedAdded == 0)
        #expect(favorites.songs.count == 2)
    }

    @Test func restoreKeepsUnmatchedLocalLikesAndRecoversOlderBackupItems() throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: folder) }
        let favorites = FavoritesStore(directory: folder), saved = SavedLibraryStore(directory: folder)
        let suite = "LibraryExportTests.\(UUID())"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let local = Track(discID: "", number: "1", title: "Later", artists: "Artist", albumTitle: "Album", coverURL: nil,
                          localSource: .init(albumID: "a", trackID: "later-id"))
        // 同一台设备上文件身份没变：标题改了也能按身份对上。
        let same = Track(discID: "", number: "2", title: "Old Title", artists: "Artist", albumTitle: "Album", coverURL: nil,
                         localSource: .init(albumID: "a", trackID: "same-id"))
        let renamed = Track(discID: "", number: "2", title: "New Title", artists: "Artist", albumTitle: "Album", coverURL: nil,
                            localSource: .init(albumID: "a", trackID: "same-id"))
        let dizzy = Track(discID: "disc9", number: "3", title: "Dizzy", artists: "Circle", albumTitle: "Disc", coverURL: nil)
        // 早期备份把 DizzyLab 的歌记在「收藏」里；网易云歌单是只在 App 里手动加入的。
        let export = LibraryExport(exportedAt: .now, favorites: [LibraryExport.Song(local, addedAt: .now), LibraryExport.Song(same)],
                                   savedSongs: [LibraryExport.Song(dizzy)], collections: [
            .init(providerID: "netease", kind: "playlist", itemID: "8", title: "手动歌单", subtitle: "", songs: [], songsComplete: false, origin: .saved),
            .init(providerID: "netease", kind: "album", itemID: "9", title: "账号专辑", subtitle: "", songs: [], songsComplete: false, origin: .account),
        ])

        // 音乐还没放回：本地喜欢暂时对不上，但不能丢。
        let first = try LibraryContext.restoreLibrary(export, favorites: favorites, saved: saved, localTracks: [renamed])
        #expect(first.unmatchedLocal == 1)
        #expect(favorites.contains(renamed))
        #expect(favorites.contains(dizzy))
        #expect(!saved.contains(.song, providerID: "dizzylab", itemID: dizzy.id))
        #expect(saved.contains(.playlist, providerID: "netease", itemID: "8"))
        #expect(!saved.contains(.album, providerID: "netease", itemID: "9"))

        // 之后的自动备份覆盖旧文件时仍带着这首。
        let backup = LibraryExport.snapshot(favorites: favorites, mirror: AccountLibraryMirror(directory: folder), saved: saved,
                                            offline: OfflineLibraryStore(defaults: defaults))
        #expect(backup.favorites.contains { $0.providerID == "local" && $0.title == "Later" && $0.itemID == "later-id" })
        #expect(!favorites.songs.contains { $0.track.title == "Later" })

        // 音乐放回后用新备份导入：对上了就从待恢复里移走。
        let moved = Track(discID: "", number: "1", title: "Later", artists: "Artist", albumTitle: "Album", coverURL: nil,
                          localSource: .init(albumID: "b", trackID: "moved-id"))
        let second = try LibraryContext.restoreLibrary(backup, favorites: favorites, saved: saved, localTracks: [renamed, moved])
        #expect(second.unmatchedLocal == 0)
        #expect(second.favoritesAdded == 1)
        #expect(favorites.contains(moved))
        #expect(favorites.unmatchedLocal.isEmpty)
        // 重新打开数据库后状态一致。
        #expect(FavoritesStore(directory: folder).unmatchedLocal.isEmpty)
    }

    @Test func moduleRestoreIgnoresUnknownModulesAndKeepsOneVisible() throws {
        let store = try #require(UserDefaults(suiteName: "LibraryExportTests.\(UUID())"))
        let modules = AppComposition.settings(modules: [ModuleDescriptor(id: ModuleID(rawValue: "fixture"), title: "Fixture", systemImage: "square"), LocalLibraryModule.metadata], defaults: store)
        modules.restore(order: [ModuleID(rawValue: "gone"), .localLibrary], hidden: [.localLibrary, ModuleID(rawValue: "fixture")],
                        startup: ModuleID(rawValue: "gone"), search: [ModuleID(rawValue: "fixture")])
        #expect(modules.order == [.localLibrary, ModuleID(rawValue: "fixture")])
        #expect(modules.visibleModules == [.localLibrary])
        #expect(modules.searchOrder.first == ModuleID(rawValue: "fixture"))
        #expect(modules.startupModule == modules.order.first || modules.startupModule == ModuleID(rawValue: "fixture"))
    }

    @Test func restoredBackupIsNotOverwrittenBeforeImport() throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: folder) }
        let store = try #require(UserDefaults(suiteName: "LibraryBackupTests.\(UUID())"))
        let backup = LibraryBackup(folder: folder, defaults: store)
        #expect(backup.interval == .daily && backup.includesNeteaseLogin)
        // 全新安装、文件夹为空：立即到期。
        #expect(backup.isDue)

        // 重装后放回旧备份：在导入前不自动覆盖。
        var old = LibraryExport(exportedAt: .now, favorites: [], savedSongs: [], collections: [])
        old.credentials = .init(neteaseCookie: "MUSIC_U=abc")
        try old.data().write(to: backup.fileURL)
        #expect(backup.hasUnimportedBackup)
        #expect(!backup.isDue)
        let (found, url) = try backup.findBackup()
        #expect(url == backup.fileURL)
        #expect(found.credentials?.neteaseCookie == "MUSIC_U=abc")

        backup.markBackedUp()
        #expect(!backup.hasUnimportedBackup)
        #expect(!backup.isDue)
        backup.interval = .off
        #expect(LibraryBackup(folder: folder, defaults: store).interval == .off)
    }

    @Test func findsRenamedBackupAndReportsMissingFolder() throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: folder) }
        let store = try #require(UserDefaults(suiteName: "LibraryBackupTests.\(UUID())"))
        let backup = LibraryBackup(folder: folder, defaults: store)
        #expect(throws: LibraryBackup.BackupError.self) { try backup.findBackup() }
        try Data("not json".utf8).write(to: folder.appending(path: "notes.json"))
        let renamed = folder.appending(path: "NeoDizzy-资料库 (1).json")
        try LibraryExport(exportedAt: .now, favorites: [], savedSongs: [], collections: []).data().write(to: renamed)
        #expect(try backup.findBackup().1.lastPathComponent == renamed.lastPathComponent)
    }

    @Test func sharedExportCarriesNoCredentials() throws {
        let export = LibraryExport(exportedAt: .now, favorites: [], savedSongs: [], collections: [])
        #expect(!String(decoding: try export.data(), as: UTF8.self).contains("credentials"))
    }
}
