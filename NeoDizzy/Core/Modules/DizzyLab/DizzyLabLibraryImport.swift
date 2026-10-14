import Foundation

extension OfflineLibraryWorker {
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
        var preservedManifestURL: URL?
        var committedManifest = manifest
        if replacing {
            let manifestURL = try OfflinePaths.file(OfflineManifest.filename, inside: target)
            if manager.fileExists(atPath: manifestURL.path) {
                let data = try Data(contentsOf: manifestURL)
                let previous = try JSONDecoder().decode(OfflineManifest.self, from: data)
                if (try JSONSerialization.jsonObject(with: data) as? [String: Any])?["version"] as? Int == 1 {
                    preservedManifestURL = manifestURL
                    committedManifest = previous
                    // 旧记录的路径必须仍然有效，不能写回新的映射。
                    try previous.validate(in: source)
                }
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
        let stagedManifest = staging.appendingPathComponent(OfflineManifest.filename)
        if let preservedManifestURL {
            // 同卷硬链接保留 v1 原件，不重新编码或写入；不支持时整次导入失败，原目录不动。
            try manager.linkItem(at: preservedManifestURL, to: stagedManifest)
        } else {
            try encoder.encode(manifest).write(to: stagedManifest, options: .atomic)
        }
        try committedManifest.validate(in: staging)
        try Task.checkCancellation()
        if replacing {
            try commit(staging, replacing: target)
        } else {
            try manager.moveItem(at: staging, to: target)
        }
        // moveItem 成功即已提交。此后不检查取消、不回删，调用方必须发布这张专辑。
        return OfflineAlbum(manifest: committedManifest, directoryURL: target)
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

}
