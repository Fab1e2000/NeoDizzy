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
    func prepare(_ url: URL) throws -> PreparedOfflineFolder {
        let access = OfflineFolderAccess(url: url)
        guard try url.resourceValues(forKeys: [.isDirectoryKey]).isDirectory == true else {
            throw OfflineLibraryError.invalidFolder
        }
        let bookmark = try url.bookmarkData(options: .minimalBookmark, includingResourceValuesForKeys: nil, relativeTo: nil)
        return PreparedOfflineFolder(access: access, bookmark: bookmark)
    }

    func restore(_ data: Data) throws -> PreparedOfflineFolder {
        var stale = false
        let url = try URL(resolvingBookmarkData: data, options: [.withoutUI], relativeTo: nil, bookmarkDataIsStale: &stale)
        // 总是刷新 bookmark，同时覆盖文件提供商迁移后已过期的 bookmark。
        return try prepare(url)
    }

    func scan(_ folder: OfflineFolderAccess) throws -> OfflineScanResult {
        try coordinatedRead(folder.url) { root in
            try Self.scanDirectory(root)
        }
    }

    func importAlbum(from extractedURL: URL, detail: DiscDetail, into folder: OfflineFolderAccess) throws -> OfflineAlbum {
        try coordinatedWrite(folder.url) { root in
            try Self.importDirectory(from: extractedURL, detail: detail, into: root)
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
                let manifest = try JSONDecoder().decode(OfflineManifest.self, from: Data(contentsOf: url))
                let directory = url.deletingLastPathComponent()
                try manifest.validate(in: directory)
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
        guard !manager.fileExists(atPath: target.path) else { throw OfflineLibraryError.existingAlbum }
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
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        try encoder.encode(manifest).write(to: staging.appendingPathComponent(OfflineManifest.filename), options: .atomic)
        try manifest.validate(in: staging)
        try Task.checkCancellation()
        try manager.moveItem(at: staging, to: target)
        // moveItem 成功即已提交。此后不检查取消、不回删，调用方必须发布这张专辑。
        return OfflineAlbum(manifest: manifest, directoryURL: target)
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
