import Foundation

/// 引用计数保证换目录时，仍在执行的扫描不会提前失去原目录的授权。
nonisolated final class OfflineFolderAccess: @unchecked Sendable {
    let url: URL
    private let hasScope: Bool

    init(url: URL) {
        self.url = url
        hasScope = url.startAccessingSecurityScopedResource()
    }

    deinit {
        if hasScope { url.stopAccessingSecurityScopedResource() }
    }
}

nonisolated struct OfflineScanResult: Sendable {
    let albums: [OfflineAlbum]
    let issues: [String]
}

nonisolated struct PreparedOfflineFolder: Sendable {
    let access: OfflineFolderAccess
    let bookmark: Data
}

/// 文件提供商的协调、目录枚举和大文件复制都在这个 actor 上执行。
actor OfflineLibraryWorker {
    #if os(macOS)
    /// 沙盒中的 Mac App 需要带安全范围的 bookmark，重启后才能重新获得用户所选文件夹的访问权限；
    /// 未沙盒的进程（例如在 macOS 上运行的核心测试）使用普通 bookmark。
    private static let usesSecurityScope = ProcessInfo.processInfo.environment["APP_SANDBOX_CONTAINER_ID"] != nil
    private static var bookmarkCreation: URL.BookmarkCreationOptions { usesSecurityScope ? .withSecurityScope : .minimalBookmark }
    private static var bookmarkResolution: URL.BookmarkResolutionOptions { usesSecurityScope ? [.withSecurityScope, .withoutUI] : [.withoutUI] }
    #else
    private static let bookmarkCreation: URL.BookmarkCreationOptions = .minimalBookmark
    private static let bookmarkResolution: URL.BookmarkResolutionOptions = [.withoutUI]
    #endif

    func prepare(_ url: URL) throws -> PreparedOfflineFolder {
        let access = OfflineFolderAccess(url: url)
        guard try url.resourceValues(forKeys: [.isDirectoryKey]).isDirectory == true,
              try url.resourceValues(forKeys: [.isSymbolicLinkKey]).isSymbolicLink != true else {
            throw OfflineLibraryError.invalidFolder
        }
        let bookmark = try url.bookmarkData(options: Self.bookmarkCreation, includingResourceValuesForKeys: nil, relativeTo: nil)
        return PreparedOfflineFolder(access: access, bookmark: bookmark)
    }

    func restore(_ data: Data) throws -> PreparedOfflineFolder {
        var stale = false
        let url = try URL(resolvingBookmarkData: data, options: Self.bookmarkResolution, relativeTo: nil, bookmarkDataIsStale: &stale)
        // 总是刷新 bookmark，同时覆盖文件提供商迁移后已过期的 bookmark。
        return try prepare(url)
    }

    func scan(_ folder: OfflineFolderAccess) throws -> OfflineScanResult {
        try coordinatedRead(folder.url) { root in
            try Self.scanDirectory(root)
        }
    }

    func availableTrackIDs(in album: OfflineAlbum, folder: OfflineFolderAccess) throws -> Set<String> {
        if album.directoryURL.standardizedFileURL.resolvingSymlinksInPath().path != folder.url.standardizedFileURL.resolvingSymlinksInPath().path {
            _ = try OfflinePaths.relativePath(of: album.directoryURL, inside: folder.url)
        }
        var ids = Set<String>()
        for entry in album.manifest.entries {
            try Task.checkCancellation()
            if album.localFile(for: entry.track) != nil { ids.insert(entry.track.id) }
        }
        return ids
    }

    func importAlbum(from extractedURL: URL, detail: DiscDetail, into folder: OfflineFolderAccess) throws -> OfflineAlbum {
        try coordinatedWrite(folder.url) { root in
            try Self.importDirectory(from: extractedURL, detail: detail, into: root)
        }
    }

    func importGift(from source: URL, detail: DiscDetail, albumDirectory: URL?, into folder: OfflineFolderAccess) throws {
        let relative = try albumDirectory.map {
            $0.standardizedFileURL.resolvingSymlinksInPath() == folder.url.standardizedFileURL.resolvingSymlinksInPath()
                ? "" : try OfflinePaths.relativePath(of: $0, inside: folder.url)
        }
        try coordinatedWrite(folder.url) { root in
            let album = try relative.map { $0.isEmpty ? root : try OfflinePaths.file($0, inside: root) }
            try Self.importGiftDirectory(from: source, detail: detail, albumDirectory: album, into: root)
        }
    }

    private func coordinatedRead<T>(_ url: URL, operation: (URL) throws -> T) throws -> T {
        let coordinator = NSFileCoordinator(filePresenter: nil)
        var coordinationError: NSError?
        var result: Result<T, Error>?
        coordinator.coordinate(readingItemAt: url, options: [], error: &coordinationError) { coordinatedURL in
            result = Result { try operation(coordinatedURL) }
        }
        if let coordinationError { throw coordinationError }
        guard let result else { throw OfflineLibraryError.invalidFolder }
        return try result.get()
    }

    private func coordinatedWrite<T>(_ url: URL, operation: (URL) throws -> T) throws -> T {
        let coordinator = NSFileCoordinator(filePresenter: nil)
        var coordinationError: NSError?
        var result: Result<T, Error>?
        coordinator.coordinate(writingItemAt: url, options: [], error: &coordinationError) { coordinatedURL in
            result = Result { try operation(coordinatedURL) }
        }
        // 写入 accessor 一旦成功，实际提交结果优先于协调器的后续状态。
        if let result { return try result.get() }
        if let coordinationError { throw coordinationError }
        throw OfflineLibraryError.invalidFolder
    }

    /// 单独保留同步核心，方便测试真实文件而不依赖文件提供商。
    nonisolated static func scanDirectory(_ root: URL) throws -> OfflineScanResult {
        let manager = FileManager.default
        guard try root.resourceValues(forKeys: [.isDirectoryKey]).isDirectory == true else {
            throw OfflineLibraryError.invalidFolder
        }
        var issues: [String] = []
        guard let enumerator = manager.enumerator(at: root, includingPropertiesForKeys: [.isDirectoryKey, .isSymbolicLinkKey], options: [.skipsPackageDescendants], errorHandler: { url, error in
            issues.append("\(url.lastPathComponent)：\(error.localizedDescription)")
            return true
        }) else { throw OfflineLibraryError.invalidFolder }
        var albums: [OfflineAlbum] = []
        for case let url as URL in enumerator {
            try Task.checkCancellation()
            do {
                let values = try url.resourceValues(forKeys: [.isDirectoryKey, .isSymbolicLinkKey])
                if values.isSymbolicLink == true {
                    enumerator.skipDescendants()
                    continue
                }
                if values.isDirectory == true {
                    if url.lastPathComponent.hasPrefix(".") || url.lastPathComponent == "__MACOSX" {
                        enumerator.skipDescendants()
                    }
                    continue
                }
                guard url.lastPathComponent == OfflineManifest.filename else { continue }
                _ = try OfflinePaths.relativePath(of: url, inside: root)
                let size = try url.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0
                guard size <= 2_000_000 else { throw OfflineLibraryError.invalidManifest }
                var manifest = try JSONDecoder().decode(OfflineManifest.self, from: Data(contentsOf: url))
                let directory = url.deletingLastPathComponent()
                do {
                    try manifest.validate(in: directory)
                } catch OfflineLibraryError.missingTrack(let title) {
                    let paths = try extractedFiles(in: directory).filter {
                        AudioFileMatcher.extensions.contains(URL(fileURLWithPath: $0).pathExtension.lowercased())
                    }
                    guard !paths.isEmpty else { throw OfflineLibraryError.missingTrack(title) }
                    do {
                        manifest = try manifest.resolvingRenamedFiles(relativePaths: paths, in: directory)
                    } catch OfflineLibraryError.missingTrack {
                        // The directory was edited externally. Let the local scanner read the
                        // current files instead of reporting a stale manifest path as an error.
                        continue
                    } catch OfflineLibraryError.ambiguousTrack {
                        // Never guess a site's track identity when multiple files could match.
                        continue
                    }
                }
                albums.append(OfflineAlbum(manifest: manifest, directoryURL: directory))
            } catch {
                issues.append("\(url.deletingLastPathComponent().lastPathComponent)：\(error.localizedDescription)")
            }
        }
        let duplicates = Set(Dictionary(grouping: albums, by: \.id).filter { $0.value.count > 1 }.keys)
        if !duplicates.isEmpty { issues.append("发现重复专辑 ID，已跳过重复目录，请保留一份后重新扫描。") }
        return OfflineScanResult(albums: albums.filter { !duplicates.contains($0.id) }.sorted {
            $0.title.localizedStandardCompare($1.title) == .orderedAscending
        }, issues: issues)
    }

    @discardableResult
    nonisolated static func importDirectory(from source: URL, detail: DiscDetail, into root: URL) throws -> OfflineAlbum {
        let manager = FileManager.default
        let paths = try extractedFiles(in: source)
        let matches = try AudioFileMatcher.match(tracks: detail.tracks, relativePaths: paths)
        let coverPath = preferredCover(in: paths)
        let manifest = try OfflineManifest(detail: detail, files: matches, coverPath: coverPath)
        try manifest.validate(in: source)

        let label = OfflinePaths.directoryName(detail.summary.labelName ?? "", fallback: "未知社团")
        let title = OfflinePaths.directoryName(detail.summary.title, fallback: "未命名专辑")
        let id = OfflinePaths.identifierName(detail.id)
        let labelURL = try OfflinePaths.file(label, inside: root)
        if manager.fileExists(atPath: labelURL.path) {
            let values = try labelURL.resourceValues(forKeys: [.isDirectoryKey, .isSymbolicLinkKey])
            guard values.isDirectory == true, values.isSymbolicLink != true else { throw OfflineLibraryError.unsafePath(label) }
        } else {
            try manager.createDirectory(at: labelURL, withIntermediateDirectories: true)
        }
        let target = try OfflinePaths.file("\(label)/\(title) [\(id)]", inside: root)
        let replacing = manager.fileExists(atPath: target.path)
        if replacing {
            let manifestURL = try OfflinePaths.file(OfflineManifest.filename, inside: target)
            if manager.fileExists(atPath: manifestURL.path) {
                let previous = try JSONDecoder().decode(OfflineManifest.self, from: Data(contentsOf: manifestURL))
                guard previous.discID == detail.id else { throw OfflineLibraryError.existingAlbum }
            } else {
                try validateGiftOnlyDirectory(target, discID: detail.id)
            }
        }
        // 同卷临时目录 → 原子移动；复制失败或取消不会留下可被扫描到的半张专辑。
        let staging = labelURL.appendingPathComponent(".neodizzy-import-\(UUID().uuidString)", isDirectory: true)
        try manager.createDirectory(at: staging, withIntermediateDirectories: false)
        defer { try? manager.removeItem(at: staging) }
        for path in paths {
            try Task.checkCancellation()
            guard URL(fileURLWithPath: path).lastPathComponent != OfflineManifest.filename else { continue }
            let sourceFile = try OfflinePaths.file(path, inside: source)
            let destination = try OfflinePaths.file(path, inside: staging)
            try manager.createDirectory(at: destination.deletingLastPathComponent(), withIntermediateDirectories: true)
            try manager.copyItem(at: sourceFile, to: destination)
        }
        if replacing, manager.fileExists(atPath: target.appendingPathComponent("特典").path) {
            let gift = try OfflinePaths.file("特典", inside: target)
            // Preserve a previously downloaded gift when the album arrives later.
            let destination = try OfflinePaths.file("特典", inside: staging)
            guard !manager.fileExists(atPath: destination.path) else { throw OfflineLibraryError.existingAlbum }
            try manager.copyItem(at: gift, to: destination)
        }
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        try encoder.encode(manifest).write(to: staging.appendingPathComponent(OfflineManifest.filename), options: .atomic)
        try manifest.validate(in: staging)
        try Task.checkCancellation()
        if replacing {
            try commit(staging, replacing: target)
        } else {
            try manager.moveItem(at: staging, to: target)
        }
        // moveItem 成功即已提交。此后不检查取消、不回删，调用方必须发布这张专辑。
        return OfflineAlbum(manifest: manifest, directoryURL: target)
    }

    private nonisolated static let giftMarker = ".neodizzy-gift.json"

    private nonisolated static func validateGiftOnlyDirectory(_ directory: URL, discID: String) throws {
        let manager = FileManager.default
        let contents = try manager.contentsOfDirectory(atPath: directory.path)
        guard Set(contents) == Set(["特典", giftMarker]),
              try String(contentsOf: OfflinePaths.file(giftMarker, inside: directory), encoding: .utf8) == discID else {
            throw OfflineLibraryError.existingAlbum
        }
    }

    /// Commit a fully prepared directory, restoring the original if the final move fails.
    private nonisolated static func commit(_ staging: URL, replacing target: URL) throws {
        let manager = FileManager.default
        let backup = target.deletingLastPathComponent().appendingPathComponent(".neodizzy-backup-\(UUID().uuidString)")
        try manager.moveItem(at: target, to: backup)
        do {
            try manager.moveItem(at: staging, to: target)
        } catch {
            try manager.moveItem(at: backup, to: target)
            throw error
        }
        try? manager.removeItem(at: backup)
    }

    nonisolated static func importGiftDirectory(from source: URL, detail: DiscDetail, albumDirectory: URL? = nil, into root: URL) throws {
        let manager = FileManager.default
        let paths = try extractedFiles(in: source)
        guard !paths.isEmpty else { throw DownloadFailure.damagedArchive }
        let label = OfflinePaths.directoryName(detail.summary.labelName ?? "", fallback: "未知社团")
        let title = OfflinePaths.directoryName(detail.summary.title, fallback: "未命名专辑")
        let id = OfflinePaths.identifierName(detail.id)
        let album = try albumDirectory ?? OfflinePaths.file("\(label)/\(title) [\(id)]", inside: root)
        if album.standardizedFileURL.resolvingSymlinksInPath() != root.standardizedFileURL.resolvingSymlinksInPath() {
            _ = try OfflinePaths.relativePath(of: album, inside: root)
        }
        let exists = manager.fileExists(atPath: album.path)
        if exists {
            let manifestURL = try OfflinePaths.file(OfflineManifest.filename, inside: album)
            if manager.fileExists(atPath: manifestURL.path) {
                let manifest = try JSONDecoder().decode(OfflineManifest.self, from: Data(contentsOf: manifestURL))
                guard manifest.discID == detail.id else { throw OfflineLibraryError.existingAlbum }
                try manifest.validate(in: album)
            } else {
                try validateGiftOnlyDirectory(album, discID: detail.id)
            }
        }
        // Keep temporary writes inside the granted folder, even when the album is the library root.
        let stagingParent = exists ? album : album.deletingLastPathComponent()
        if !exists { try manager.createDirectory(at: stagingParent, withIntermediateDirectories: true) }
        let staging = stagingParent.appendingPathComponent(".neodizzy-gift-\(UUID().uuidString)", isDirectory: true)
        try manager.createDirectory(at: staging, withIntermediateDirectories: false)
        defer { try? manager.removeItem(at: staging) }
        let contents = staging.appendingPathComponent("特典", isDirectory: true)
        try manager.createDirectory(at: contents, withIntermediateDirectories: false)
        for path in paths {
            try Task.checkCancellation()
            // Archive metadata must never become another scanned album.
            guard URL(fileURLWithPath: path).lastPathComponent != OfflineManifest.filename else { continue }
            let destination = try OfflinePaths.file(path, inside: contents)
            try manager.createDirectory(at: destination.deletingLastPathComponent(), withIntermediateDirectories: true)
            try manager.copyItem(at: OfflinePaths.file(path, inside: source), to: destination)
        }
        try detail.id.write(to: contents.appendingPathComponent(giftMarker), atomically: true, encoding: .utf8)
        try Task.checkCancellation()
        if exists {
            let target = try OfflinePaths.file("特典", inside: album)
            if manager.fileExists(atPath: target.path) {
                let marker = try OfflinePaths.file(giftMarker, inside: target)
                guard (try? String(contentsOf: marker, encoding: .utf8)) == detail.id else {
                    throw OfflineLibraryError.existingAlbum
                }
                try commit(contents, replacing: target)
            } else {
                try manager.moveItem(at: contents, to: target)
            }
        } else {
            try detail.id.write(to: staging.appendingPathComponent(giftMarker), atomically: true, encoding: .utf8)
            try manager.moveItem(at: staging, to: album)
        }
    }

    private nonisolated static func extractedFiles(in root: URL) throws -> [String] {
        guard try root.resourceValues(forKeys: [.isDirectoryKey]).isDirectory == true else {
            throw OfflineLibraryError.invalidFolder
        }
        var enumerationError: Error?
        guard let enumerator = FileManager.default.enumerator(at: root,
            includingPropertiesForKeys: [.isDirectoryKey, .isRegularFileKey, .isSymbolicLinkKey], options: [],
            errorHandler: { _, error in enumerationError = error; return false }) else {
            throw OfflineLibraryError.invalidFolder
        }
        var paths: [String] = []
        for case let url as URL in enumerator {
            try Task.checkCancellation()
            let values = try url.resourceValues(forKeys: [.isDirectoryKey, .isRegularFileKey, .isSymbolicLinkKey])
            guard values.isSymbolicLink != true else { throw OfflineLibraryError.unsafePath(url.lastPathComponent) }
            if url.lastPathComponent == "__MACOSX" || url.lastPathComponent.hasPrefix(".") {
                if values.isDirectory == true { enumerator.skipDescendants() }
                continue
            }
            if values.isDirectory == true { continue }
            guard values.isRegularFile == true else { throw OfflineLibraryError.unsafePath(url.lastPathComponent) }
            paths.append(try OfflinePaths.relativePath(of: url, inside: root))
        }
        if let enumerationError { throw enumerationError }
        return paths
    }

    private nonisolated static func preferredCover(in paths: [String]) -> String? {
        let images = paths.filter { ["jpg", "jpeg", "png", "heic", "webp"].contains(URL(fileURLWithPath: $0).pathExtension.lowercased()) }
        for name in ["cover", "folder", "front", "封面"] {
            let matches = images.filter { URL(fileURLWithPath: $0).deletingPathExtension().lastPathComponent.lowercased() == name }
            if matches.count == 1 { return matches[0] }
        }
        return images.count == 1 ? images[0] : nil
    }
}
