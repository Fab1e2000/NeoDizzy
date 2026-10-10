import Foundation

/// 把用户从「文件」或其他 App 交来的歌曲、歌词、封面和 ZIP 放进 App 自己的音乐文件夹。
///
/// 本地库以文件所在的文件夹作为专辑边界，所以零散歌曲按专辑标签分到同名文件夹；
/// 同一次选中的歌词和封面跟着同名歌曲走。ZIP 解压成一个以压缩包命名的文件夹。
nonisolated enum LibraryImporter {
    struct Summary: Sendable, Equatable {
        var tracks = 0
        var archives = 0
        var duplicates = 0
        var alreadyInLibrary = 0
        var skipped: [String] = []

        var message: String {
            var parts: [String] = []
            if tracks > 0 { parts.append("已导入 \(tracks) 首歌曲") }
            if archives > 0 { parts.append("已解压 \(archives) 个压缩包") }
            if duplicates > 0 { parts.append("\(duplicates) 个文件已存在，已跳过") }
            if alreadyInLibrary > 0 { parts.append("\(alreadyInLibrary) 个文件已在音乐文件夹中") }
            if parts.isEmpty, skipped.isEmpty { parts.append("没有可导入的文件") }
            return (parts + skipped.prefix(5)).joined(separator: "\n")
        }
    }

    /// 未写专辑标签的歌曲放进这个文件夹。
    static let unsortedFolder = "导入的歌曲"
    static let sidecarExtensions: Set<String> = ["lrc", "jpg", "jpeg", "png", "heic", "webp"]

    @concurrent
    static func importItems(_ urls: [URL], into root: URL,
                            albumTitle: @escaping @Sendable (URL) async -> String? = { try? await AudioMetadataReader.read($0).album }) async throws -> Summary {
        var summary = Summary()
        var audio: [URL] = []
        var sidecars: [URL] = []
        // 分享菜单交来的文件可能还在原位置，需要临时授权；选择器复制来的文件不需要，调用也无害。
        let scoped = urls.filter { $0.startAccessingSecurityScopedResource() }
        defer { scoped.forEach { $0.stopAccessingSecurityScopedResource() } }
        for url in urls {
            try Task.checkCancellation()
            // 在「文件」里打开音乐文件夹中已有的文件时，不再复制一份。
            if (try? OfflinePaths.relativePath(of: url, inside: root)) != nil,
               (try? OfflinePaths.relativePath(of: url, inside: inbox(of: root))) == nil {
                summary.alreadyInLibrary += 1
                continue
            }
            let ext = url.pathExtension.lowercased()
            let isDirectory = (try? url.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true
            if isDirectory {
                summary.tracks += try copyFolder(url, into: root)
            } else if ext == "zip" {
                do {
                    summary.tracks += try await extractArchive(url, into: root)
                    summary.archives += 1
                } catch is CancellationError { throw CancellationError() }
                catch { summary.skipped.append("\(url.lastPathComponent)：\(error.localizedDescription)") }
            } else if AudioFileMatcher.extensions.contains(ext) {
                audio.append(url)
            } else if sidecarExtensions.contains(ext) {
                sidecars.append(url)
            } else {
                summary.skipped.append("\(url.lastPathComponent)：不是支持的音乐文件")
            }
        }

        var groups: [String: [URL]] = [:]
        for url in audio {
            try Task.checkCancellation()
            let title = await albumTitle(url)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            groups[OfflinePaths.directoryName(title, fallback: unsortedFolder), default: []].append(url)
        }
        var groupOfStem: [String: String] = [:]
        for (name, files) in groups {
            for file in files { groupOfStem[stem(file)] = name }
        }
        for url in sidecars {
            // 歌词跟着同名歌曲；只导入一张专辑时，封面等其余文件也放进去。
            if let name = groupOfStem[stem(url)] ?? (groups.count == 1 ? groups.keys.first : nil) {
                groups[name, default: []].append(url)
            } else {
                summary.skipped.append("\(url.lastPathComponent)：没有对应的歌曲，未导入")
            }
        }

        let manager = FileManager.default
        for name in groups.keys.sorted() {
            let folder = try albumFolder(named: name, in: root)
            for url in groups[name]! {
                try Task.checkCancellation()
                let target = folder.appendingPathComponent(url.lastPathComponent)
                if manager.fileExists(atPath: target.path) {
                    if size(of: target) == size(of: url) {
                        summary.duplicates += 1
                        continue
                    }
                    try transfer(url, to: uniqueURL(target), root: root)
                } else {
                    try transfer(url, to: target, root: root)
                }
                if AudioFileMatcher.extensions.contains(url.pathExtension.lowercased()) { summary.tracks += 1 }
            }
        }
        return summary
    }

    /// 解压到隐藏的临时文件夹再整体移入，扫描不会读到半个压缩包。
    private static func extractArchive(_ zip: URL, into root: URL) async throws -> Int {
        let staging = root.appendingPathComponent(".neodizzy-import-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: staging) }
        try await SafeZipExtractor.extract(zip, into: staging, preferLegacyEncoding: SafeZipExtractor.gbk)
        let manager = FileManager.default
        let visible = try manager.contentsOfDirectory(at: staging, includingPropertiesForKeys: [.isDirectoryKey])
            .filter { !$0.lastPathComponent.hasPrefix(".") && $0.lastPathComponent != "__MACOSX" }
        // 压缩包里只有一个文件夹时直接用它，避免多套一层。
        let source: URL
        let name: String
        if visible.count == 1, (try? visible[0].resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true {
            source = visible[0]
            name = visible[0].lastPathComponent
        } else {
            source = staging
            name = zip.deletingPathExtension().lastPathComponent
        }
        let count = audioCount(in: source)
        guard count > 0 else { throw LibraryImportError.noAudio }
        try manager.moveItem(at: source, to: uniqueURL(root.appendingPathComponent(OfflinePaths.directoryName(name, fallback: unsortedFolder), isDirectory: true)))
        return count
    }

    private static func copyFolder(_ folder: URL, into root: URL) throws -> Int {
        let count = audioCount(in: folder)
        guard count > 0 else { throw LibraryImportError.noAudio }
        let name = OfflinePaths.directoryName(folder.lastPathComponent, fallback: unsortedFolder)
        try FileManager.default.copyItem(at: folder, to: uniqueURL(root.appendingPathComponent(name, isDirectory: true)))
        return count
    }

    /// 同名文件夹已有零散歌曲时继续放进去；下载的专辑（有对应关系文件）不混入别的文件。
    private static func albumFolder(named name: String, in root: URL) throws -> URL {
        let manager = FileManager.default
        let folder = root.appendingPathComponent(name, isDirectory: true)
        var isDirectory: ObjCBool = false
        if manager.fileExists(atPath: folder.path, isDirectory: &isDirectory) {
            if isDirectory.boolValue, !manager.fileExists(atPath: folder.appendingPathComponent(OfflineManifest.filename).path) {
                return folder
            }
            let unique = uniqueURL(folder)
            try manager.createDirectory(at: unique, withIntermediateDirectories: false)
            return unique
        }
        try manager.createDirectory(at: folder, withIntermediateDirectories: true)
        return folder
    }

    /// 选择器和分享菜单复制来的临时文件直接移动，原位置的文件只复制，不改动。
    private static func transfer(_ source: URL, to target: URL, root: URL) throws {
        let manager = FileManager.default
        if isTemporaryCopy(source, root: root) {
            try manager.moveItem(at: source, to: target)
        } else {
            try manager.copyItem(at: source, to: target)
        }
    }

    private static func isTemporaryCopy(_ url: URL, root: URL) -> Bool {
        let path = LocalLibraryScanner.canonical(url)
        let inboxes = [manager.temporaryDirectory, inbox(of: root)]
            .map { LocalLibraryScanner.canonical($0) + "/" }
        return inboxes.contains { path.hasPrefix($0) }
    }

    /// 系统把分享来的文件放在 Documents/Inbox，也就是音乐文件夹里，需要移出来。
    private static func inbox(of root: URL) -> URL {
        root.appendingPathComponent("Inbox", isDirectory: true)
    }

    private static var manager: FileManager { .default }

    static func uniqueURL(_ url: URL) -> URL {
        guard manager.fileExists(atPath: url.path) else { return url }
        // 文件夹名里的点（如「Vol.1」）不是扩展名。
        let base = url.hasDirectoryPath ? url.lastPathComponent : url.deletingPathExtension().lastPathComponent
        let ext = url.hasDirectoryPath ? "" : url.pathExtension
        let parent = url.deletingLastPathComponent()
        for index in 2... {
            let name = ext.isEmpty ? "\(base) \(index)" : "\(base) \(index).\(ext)"
            let candidate = parent.appendingPathComponent(name)
            if !manager.fileExists(atPath: candidate.path) { return candidate }
        }
        return url
    }

    private static func stem(_ url: URL) -> String {
        url.deletingPathExtension().lastPathComponent.precomposedStringWithCanonicalMapping
    }

    private static func size(of url: URL) -> Int? {
        try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize
    }

    private static func audioCount(in folder: URL) -> Int {
        let enumerator = manager.enumerator(at: folder, includingPropertiesForKeys: nil, options: [.skipsHiddenFiles])
        var count = 0
        while let url = enumerator?.nextObject() as? URL {
            if AudioFileMatcher.extensions.contains(url.pathExtension.lowercased()) { count += 1 }
        }
        return count
    }
}

nonisolated enum LibraryImportError: LocalizedError {
    case noAudio

    var errorDescription: String? {
        switch self {
        case .noAudio: "里面没有支持的音乐文件"
        }
    }
}
