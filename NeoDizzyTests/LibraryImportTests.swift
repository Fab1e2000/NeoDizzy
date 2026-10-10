import Foundation
import Testing
@testable import NeoDizzy

struct LibraryImportTests {
    private func temporaryDirectory() throws -> URL {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        return root
    }

    private func file(_ name: String, in folder: URL, contents: String? = nil) throws -> URL {
        let url = folder.appendingPathComponent(name)
        try Data((contents ?? "test " + name).utf8).write(to: url)
        return url
    }

    /// 测试用的专辑标签：文件名「专辑名 - 曲名.flac」。
    private let albumFromName: @Sendable (URL) async -> String? = { url in
        let name = url.deletingPathExtension().lastPathComponent
        guard let range = name.range(of: " - ") else { return nil }
        return String(name[..<range.lowerBound])
    }

    @Test func groupsLooseFilesByAlbumTagWithMatchingLyrics() async throws {
        let base = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: base) }
        let picked = base.appendingPathComponent("picked", isDirectory: true)
        let root = base.appendingPathComponent("library", isDirectory: true)
        try FileManager.default.createDirectory(at: picked, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let urls = [
            try file("星海 - 01.flac", in: picked),
            try file("星海 - 01.lrc", in: picked),
            try file("夜航 - 02.mp3", in: picked),
            try file("无标签.m4a", in: picked),
            try file("cover.jpg", in: picked),
            try file("说明.txt", in: picked),
        ]
        let summary = try await LibraryImporter.importItems(urls, into: root, albumTitle: albumFromName)
        #expect(summary.tracks == 3)
        let manager = FileManager.default
        #expect(manager.fileExists(atPath: root.appendingPathComponent("星海/星海 - 01.flac").path))
        #expect(manager.fileExists(atPath: root.appendingPathComponent("星海/星海 - 01.lrc").path))
        #expect(manager.fileExists(atPath: root.appendingPathComponent("夜航/夜航 - 02.mp3").path))
        #expect(manager.fileExists(atPath: root.appendingPathComponent("\(LibraryImporter.unsortedFolder)/无标签.m4a").path))
        // 三张专辑时封面不知道属于哪张，不导入；不支持的文件也不导入。
        #expect(summary.skipped.count == 2)
        #expect(!manager.fileExists(atPath: root.appendingPathComponent("星海/cover.jpg").path))
        // 选择器复制来的临时文件移动而不是复制。
        #expect(!manager.fileExists(atPath: urls[0].path))
    }

    @Test func singleAlbumKeepsCoverAndSkipsDuplicates() async throws {
        let base = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: base) }
        let root = base.appendingPathComponent("library", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let first = base.appendingPathComponent("first", isDirectory: true)
        try FileManager.default.createDirectory(at: first, withIntermediateDirectories: true)
        let summary = try await LibraryImporter.importItems([
            try file("星海 - 01.flac", in: first),
            try file("cover.jpg", in: first),
        ], into: root, albumTitle: albumFromName)
        #expect(summary.tracks == 1)
        #expect(FileManager.default.fileExists(atPath: root.appendingPathComponent("星海/cover.jpg").path))

        let second = base.appendingPathComponent("second", isDirectory: true)
        try FileManager.default.createDirectory(at: second, withIntermediateDirectories: true)
        let again = try await LibraryImporter.importItems([
            try file("星海 - 01.flac", in: second),
            try file("星海 - 02.flac", in: second),
        ], into: root, albumTitle: albumFromName)
        #expect(again.duplicates == 1)
        #expect(again.tracks == 1)
        // 同名专辑的新歌放进原来的文件夹。
        #expect(FileManager.default.fileExists(atPath: root.appendingPathComponent("星海/星海 - 02.flac").path))
        #expect(!FileManager.default.fileExists(atPath: root.appendingPathComponent("星海 2").path))
    }

    @Test func doesNotMixLooseFilesIntoDownloadedAlbum() async throws {
        let base = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: base) }
        let root = base.appendingPathComponent("library", isDirectory: true)
        let downloaded = root.appendingPathComponent("星海", isDirectory: true)
        try FileManager.default.createDirectory(at: downloaded, withIntermediateDirectories: true)
        _ = try file(OfflineManifest.filename, in: downloaded, contents: "{}")
        let picked = base.appendingPathComponent("picked", isDirectory: true)
        try FileManager.default.createDirectory(at: picked, withIntermediateDirectories: true)
        _ = try await LibraryImporter.importItems([try file("星海 - 01.flac", in: picked)], into: root, albumTitle: albumFromName)
        #expect(FileManager.default.fileExists(atPath: root.appendingPathComponent("星海 2/星海 - 01.flac").path))
    }

    @Test func extractsArchiveIntoItsOwnFolder() async throws {
        let base = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: base) }
        let root = base.appendingPathComponent("library", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        // 压缩包里只有「专辑」一个文件夹，直接用它，不再多套一层。
        let nested = base.appendingPathComponent("nested.zip")
        try Fixture.data("download-utf8.zip").write(to: nested)
        // GBK 文件名的歌曲直接在压缩包根目录，用压缩包名作文件夹名。
        let flat = base.appendingPathComponent("平铺.zip")
        try Fixture.data("download-gbk.zip").write(to: flat)
        let summary = try await LibraryImporter.importItems([nested, flat], into: root, albumTitle: albumFromName)
        #expect(summary.archives == 2)
        #expect(summary.tracks == 2)
        #expect(FileManager.default.fileExists(atPath: root.appendingPathComponent("专辑/01. 星光.mp3").path))
        #expect(FileManager.default.fileExists(atPath: root.appendingPathComponent("平铺/01. 星光.mp3").path))
        let hidden = try FileManager.default.contentsOfDirectory(atPath: root.path).filter { $0.hasPrefix(".") }
        #expect(hidden.isEmpty)
    }

    @Test func leavesFilesAlreadyInTheLibraryAlone() async throws {
        let root = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let folder = root.appendingPathComponent("星海", isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let existing = try file("星海 - 01.flac", in: folder)
        let summary = try await LibraryImporter.importItems([existing], into: root, albumTitle: albumFromName)
        #expect(summary.alreadyInLibrary == 1)
        #expect(summary.tracks == 0)
        #expect(try FileManager.default.contentsOfDirectory(atPath: folder.path) == ["星海 - 01.flac"])
    }

    @Test func movesSharedFilesOutOfTheInbox() async throws {
        let root = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let inbox = root.appendingPathComponent("Inbox", isDirectory: true)
        try FileManager.default.createDirectory(at: inbox, withIntermediateDirectories: true)
        let shared = try file("星海 - 01.flac", in: inbox)
        let summary = try await LibraryImporter.importItems([shared], into: root, albumTitle: albumFromName)
        #expect(summary.tracks == 1)
        #expect(!FileManager.default.fileExists(atPath: shared.path))
        #expect(FileManager.default.fileExists(atPath: root.appendingPathComponent("星海/星海 - 01.flac").path))
    }

    @Test func duplicateSharedToInboxIsRemoved() async throws {
        let root = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let album = root.appendingPathComponent("星海", isDirectory: true)
        try FileManager.default.createDirectory(at: album, withIntermediateDirectories: true)
        _ = try file("星海 - 01.flac", in: album)
        let inbox = root.appendingPathComponent("Inbox", isDirectory: true)
        try FileManager.default.createDirectory(at: inbox, withIntermediateDirectories: true)
        let shared = try file("星海 - 01.flac", in: inbox)
        let unsupported = try file("说明.txt", in: inbox)
        let summary = try await LibraryImporter.importItems([shared, unsupported], into: root, albumTitle: albumFromName)
        #expect(summary.duplicates == 1)
        // 跳过的副本也不能留在 Inbox，否则会被扫描成一张「Inbox」专辑。
        #expect(try FileManager.default.contentsOfDirectory(atPath: inbox.path).isEmpty)
        #expect(try FileManager.default.contentsOfDirectory(atPath: album.path) == ["星海 - 01.flac"])
    }

    @Test func sameNameImageBecomesAlbumCover() async throws {
        let base = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: base) }
        let root = base.appendingPathComponent("library", isDirectory: true)
        let picked = base.appendingPathComponent("picked", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: picked, withIntermediateDirectories: true)
        _ = try await LibraryImporter.importItems([
            try file("星海 - 01.flac", in: picked),
            try file("星海 - 01.webp", in: picked),
        ], into: root, albumTitle: albumFromName)
        let folder = root.appendingPathComponent("星海", isDirectory: true)
        #expect(LocalLibraryScanner.cover(in: folder)?.lastPathComponent == "cover.webp")

        // 已有封面时，后来的图片保留原名，不覆盖封面。
        _ = try await LibraryImporter.importItems([
            try file("星海 - 02.flac", in: picked),
            try file("星海 - 02.png", in: picked),
        ], into: root, albumTitle: albumFromName)
        #expect(FileManager.default.fileExists(atPath: folder.appendingPathComponent("星海 - 02.png").path))
        #expect(LocalLibraryScanner.cover(in: folder)?.lastPathComponent == "cover.webp")
    }

    @Test @MainActor func appFolderLibraryForgetsExternalFoldersAndIndexesImports() async throws {
        let base = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: base) }
        let root = base.appendingPathComponent("Documents", isDirectory: true)
        let suite = "LibraryImport.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        defaults.set(Data([1]), forKey: "offlineLibrary.folderBookmark.v1")
        defaults.set(Data([2]), forKey: "localLibrary.scanFolders.v1")
        let scanner = LocalLibraryScanner(cacheURL: base.appendingPathComponent("cache"), readMetadata: { url in
            AudioMetadata(title: url.deletingPathExtension().lastPathComponent, album: "", artist: "演奏者", albumArtist: "", trackNumber: 1, duration: 2)
        })
        let library = OfflineLibraryStore(defaults: defaults, scanner: scanner, libraryRoot: root)
        #expect(defaults.data(forKey: "offlineLibrary.folderBookmark.v1") == nil)
        #expect(defaults.data(forKey: "localLibrary.scanFolders.v1") == nil)
        #expect(library.folderName != nil)
        await library.restore()
        #expect(library.localAlbums.isEmpty)

        let picked = base.appendingPathComponent("picked", isDirectory: true)
        try FileManager.default.createDirectory(at: picked, withIntermediateDirectories: true)
        await library.importItems([try file("01.flac", in: picked)])
        #expect(library.importMessage == "已导入 1 首歌曲")
        // 测试文件不是真正的音频，读不到专辑标签，放进「导入的歌曲」。
        #expect(library.localAlbums.map(\.title) == [LibraryImporter.unsortedFolder])
    }
}
