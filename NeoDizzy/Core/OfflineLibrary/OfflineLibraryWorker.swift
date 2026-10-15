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
    let albums: [LibraryCollection]
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
        let result = try coordinatedRead(folder.url) { root in
            try Self.scanDirectory(root)
        }
        guard result.albums.contains(where: Self.hasLegacyNeteaseName) else { return result }
        return try coordinatedWrite(folder.url) { root in
            if try Self.migrateNeteaseAlbumNames(result.albums, in: root) {
                return try Self.scanDirectory(root)
            }
            return result
        }
    }

    func availableTrackIDs(in album: LibraryCollection, folder: OfflineFolderAccess) throws -> Set<String> {
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

    func availableTrackKeys(in record: LibraryCollection, folder: OfflineFolderAccess) throws -> Set<RemoteTrackKey> {
        if record.directoryURL.standardizedFileURL.resolvingSymlinksInPath() != folder.url.standardizedFileURL.resolvingSymlinksInPath() {
            _ = try OfflinePaths.relativePath(of: record.directoryURL, inside: folder.url)
        }
        return try coordinatedRead(record.directoryURL) { _ in
            var keys = Set<RemoteTrackKey>()
            for entry in record.manifest.entries {
                try Task.checkCancellation()
                if record.localFile(for: entry.track) != nil {
                    keys.insert(RemoteTrackKey(provider: record.manifest.source.provider, itemID: entry.itemID))
                }
            }
            return keys
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

    func coordinatedWrite<T>(_ url: URL, operation: (URL) throws -> T) throws -> T {
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
        var albums: [LibraryCollection] = []
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
                guard url.lastPathComponent == LibraryManifest.filename else { continue }
                _ = try OfflinePaths.relativePath(of: url, inside: root)
                let size = try url.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0
                guard size <= 2_000_000 else { throw OfflineLibraryError.invalidManifest }
                var manifest = try JSONDecoder().decode(LibraryManifest.self, from: Data(contentsOf: url))
                let directory = url.deletingLastPathComponent()
                do {
                    try manifest.validate(in: directory)
                } catch OfflineLibraryError.missingTrack {
                    let paths = try extractedFiles(in: directory).filter {
                        AudioFileMatcher.extensions.contains(URL(fileURLWithPath: $0).pathExtension.lowercased())
                    }
                    // An empty album left by a previous deletion is not a broken download.
                    guard !paths.isEmpty else { continue }
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
                albums.append(LibraryCollection(manifest: manifest, directoryURL: directory))
            } catch {
                issues.append("\(url.deletingLastPathComponent().lastPathComponent)：\(error.localizedDescription)")
            }
        }
        let duplicates = Set(Dictionary(grouping: albums, by: { $0.manifest.source }).filter { $0.value.count > 1 }.keys)
        if !duplicates.isEmpty { issues.append("发现重复专辑 ID，已跳过重复目录，请保留一份后重新扫描。") }
        return OfflineScanResult(albums: albums.filter { !duplicates.contains($0.manifest.source) }.sorted {
            $0.title.localizedStandardCompare($1.title) == .orderedAscending
        }, issues: issues)
    }

    /// Commit a fully prepared directory, restoring the original if the final move fails.
    nonisolated static func commit(_ staging: URL, replacing target: URL) throws {
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

    nonisolated static func extractedFiles(in root: URL) throws -> [String] {
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

    nonisolated static func preferredCover(in paths: [String]) -> String? {
        let images = paths.filter { ["jpg", "jpeg", "png", "heic", "webp"].contains(URL(fileURLWithPath: $0).pathExtension.lowercased()) }
        for name in ["cover", "folder", "front", "封面"] {
            let matches = images.filter { URL(fileURLWithPath: $0).deletingPathExtension().lastPathComponent.lowercased() == name }
            if matches.count == 1 { return matches[0] }
        }
        return images.count == 1 ? images[0] : nil
    }
}
