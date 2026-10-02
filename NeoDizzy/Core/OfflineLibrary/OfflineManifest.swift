import Foundation
import CryptoKit

/// 随音频保存在专辑目录中，不保存账号、token 或会过期的播放地址。
nonisolated struct OfflineManifest: Codable, Sendable {
    static let filename = ".neodizzy.json"
    static let currentVersion = 1

    struct Entry: Codable, Sendable {
        let track: Track
        let relativePath: String
    }

    let version: Int
    let discID: String
    let title: String
    let labelName: String
    let releaseDate: String?
    let description: String
    let credits: String
    let labelDescription: String
    let artworkURL: URL?
    let coverPath: String?
    private(set) var entries: [Entry]

    init(detail: DiscDetail, files: [String: String], coverPath: String?) throws {
        guard !detail.id.isEmpty, !detail.tracks.isEmpty,
              Set(detail.tracks.map(\.number)).count == detail.tracks.count,
              detail.tracks.allSatisfy({ $0.discID == detail.id && !$0.number.isEmpty && $0.localSource == nil }) else {
            throw OfflineLibraryError.invalidManifest
        }
        version = Self.currentVersion
        discID = detail.id
        title = detail.summary.title
        labelName = detail.summary.labelName ?? "未知社团"
        releaseDate = detail.releaseDate
        description = detail.description
        credits = detail.credits
        labelDescription = detail.labelDescription
        artworkURL = detail.summary.coverURL
        self.coverPath = coverPath
        entries = try detail.tracks.map { track in
            guard let path = files[track.number] else {
                throw OfflineLibraryError.missingTrack(track.title)
            }
            return Entry(track: track, relativePath: path)
        }
    }

    func validate(in directory: URL) throws {
        try validateStructure(in: directory)
        for entry in entries {
            guard try fileExists(entry, in: directory) else {
                throw OfflineLibraryError.missingTrack(entry.track.title)
            }
        }
    }

    /// Repair only the in-memory index. Never rewrite the user's manifest or audio files.
    func resolvingRenamedFiles(relativePaths: [String], in directory: URL) throws -> OfflineManifest {
        try validateStructure(in: directory)
        let matches = try AudioFileMatcher.match(tracks: entries.map(\.track), relativePaths: relativePaths)
        for entry in entries where try fileExists(entry, in: directory) {
            // Existing, explicit associations win. Do not silently reshuffle them by filename.
            guard matches[entry.track.number] == entry.relativePath else {
                throw OfflineLibraryError.ambiguousTrack(entry.track.title)
            }
        }
        var resolved = self
        resolved.entries = try entries.map { entry in
            guard let path = matches[entry.track.number] else { throw OfflineLibraryError.missingTrack(entry.track.title) }
            return Entry(track: entry.track, relativePath: path)
        }
        try resolved.validate(in: directory)
        return resolved
    }

    private func fileExists(_ entry: Entry, in directory: URL) throws -> Bool {
        let url = try OfflinePaths.file(entry.relativePath, inside: directory)
        guard AudioFileMatcher.extensions.contains(url.pathExtension.lowercased()) else { return false }
        do { return try url.resourceValues(forKeys: [.isRegularFileKey]).isRegularFile == true }
        catch let error as CocoaError where error.code == .fileReadNoSuchFile || error.code == .fileNoSuchFile {
            return false
        }
    }

    private func validateStructure(in directory: URL) throws {
        guard version == Self.currentVersion, !discID.isEmpty, !entries.isEmpty,
              Set(entries.map { $0.track.number }).count == entries.count,
              Set(entries.map(\.relativePath)).count == entries.count,
              entries.allSatisfy({ $0.track.discID == discID && !$0.track.number.isEmpty && $0.track.localSource == nil }),
              artworkURL == nil || ["https", "http"].contains(artworkURL?.scheme?.lowercased() ?? "") else {
            throw OfflineLibraryError.invalidManifest
        }
        for entry in entries {
            _ = try OfflinePaths.file(entry.relativePath, inside: directory)
        }
        // 封面丢失不影响音频，但路径本身仍须合法。
        if let coverPath { _ = try OfflinePaths.file(coverPath, inside: directory) }
    }
}

nonisolated struct OfflineAlbum: Identifiable, Codable, Sendable {
    let manifest: OfflineManifest
    let directoryURL: URL

    var discID: String { manifest.discID }
    var id: String { discID }
    var title: String { manifest.title }
    var labelName: String { manifest.labelName }
    var coverURL: URL? {
        if let path = manifest.coverPath,
           let url = try? OfflinePaths.file(path, inside: directoryURL),
           (try? url.resourceValues(forKeys: [.isRegularFileKey]).isRegularFile) == true {
            return url
        }
        return manifest.artworkURL
    }
    var tracks: [Track] {
        manifest.entries.map { entry in
            let track = entry.track
            return Track(discID: track.discID, number: track.number, title: track.title,
                         artists: track.artists, albumTitle: title, coverURL: coverURL,
                         duration: track.duration)
        }
    }
    var detail: DiscDetail {
        let summary = DiscSummary(id: id, title: title, coverURL: coverURL, labelName: labelName, isOwned: true)
        return DiscDetail(summary: summary, releaseDate: manifest.releaseDate,
                          description: manifest.description, credits: manifest.credits,
                          labelDescription: manifest.labelDescription, hasGift: false,
                          tracks: tracks, streams: [:])
    }

    func localFile(for track: Track) -> URL? {
        guard track.discID == id,
              (try? directoryURL.resourceValues(forKeys: [.isSymbolicLinkKey]).isSymbolicLink) == false,
              let entry = manifest.entries.first(where: { $0.track.number == track.number }),
              let url = try? OfflinePaths.file(entry.relativePath, inside: directoryURL),
              (try? url.resourceValues(forKeys: [.isRegularFileKey]).isRegularFile) == true else { return nil }
        return url
    }
}

nonisolated enum OfflineLibraryError: LocalizedError, Equatable {
    case noFolder
    case invalidFolder
    case invalidManifest
    case unsafePath(String)
    case missingTrack(String)
    case ambiguousTrack(String)
    case existingAlbum
    case importing
    case folderChanged

    var errorDescription: String? {
        switch self {
        case .noFolder: "请先选择保存离线音乐的文件夹。"
        case .invalidFolder: "无法访问这个文件夹，请重新选择并授权。"
        case .invalidManifest: "离线专辑的对应关系文件无效或版本不受支持。"
        case .unsafePath: "专辑中存在不安全的文件路径，已停止导入。"
        case .missingTrack(let title): "没有找到曲目「\(title)」的音频文件。"
        case .ambiguousTrack(let title): "曲目「\(title)」对应多个文件，无法确定正确音频。"
        case .existingAlbum: "目标专辑目录已存在。请保留或移走原目录后再下载。"
        case .importing: "正在保存下载的专辑，请完成后再切换文件夹。"
        case .folderChanged: "离线文件夹已更改，请重新下载。"
        }
    }
}

nonisolated enum OfflinePaths {
    /// 不允许相对路径逃逸，也不跟随指向专辑目录外部的符号链接。
    static func file(_ path: String, inside root: URL) throws -> URL {
        let components = path.split(separator: "/", omittingEmptySubsequences: false)
        guard !path.isEmpty, !path.contains("\\"), !path.contains("\0"),
              components.allSatisfy({ !$0.isEmpty && $0 != "." && $0 != ".." }) else {
            throw OfflineLibraryError.unsafePath(path)
        }
        let base = root.standardizedFileURL.resolvingSymlinksInPath()
        let prefix = base.path.hasSuffix("/") ? base.path : base.path + "/"
        var resolved = base
        // 整条路径尚不存在时，Foundation 可能不解析已有父目录的别名。
        // 从已解析的根逐级检查，既允许新建目录，也能及早发现外逃的父符号链接。
        for component in components {
            let child = resolved.appendingPathComponent(String(component)).standardizedFileURL
            if (try? child.resourceValues(forKeys: [.isSymbolicLinkKey]))?.isSymbolicLink == true,
               !FileManager.default.fileExists(atPath: child.path) {
                throw OfflineLibraryError.unsafePath(path)
            }
            resolved = child.resolvingSymlinksInPath()
            guard resolved.path == base.path || resolved.path.hasPrefix(prefix) else {
                throw OfflineLibraryError.unsafePath(path)
            }
        }
        guard resolved.path.hasPrefix(prefix) else {
            throw OfflineLibraryError.unsafePath(path)
        }
        // 保留文件选择器授予访问权限的原始 URL，真实路径仅用于边界校验。
        return root.appendingPathComponent(path).standardizedFileURL
    }

    static func relativePath(of file: URL, inside root: URL) throws -> String {
        // 文件协调器、bookmark 和枚举器可能分别返回 /var 与 /private/var。
        // 优先用真实路径；尚未创建的后代可能保留原别名，需再比较原始路径。
        // 两种情况均交给 file 逐级验证，防止尚不存在的目标绕过父符号链接检查。
        let rootPath = root.standardizedFileURL.resolvingSymlinksInPath().path
        let filePath = file.standardizedFileURL.resolvingSymlinksInPath().path
        let prefix = rootPath.hasSuffix("/") ? rootPath : rootPath + "/"
        let path: String
        if filePath.hasPrefix(prefix) {
            path = String(filePath.dropFirst(prefix.count))
        } else {
            // Keep the original spelling here. On iOS, standardizing an existing
            // /private/var directory can return /var while a missing descendant
            // retains /private/var. Standardizing both breaks this fallback.
            let originalRoot = root.path
            let originalFile = file.path
            let originalPrefix = originalRoot.hasSuffix("/") ? originalRoot : originalRoot + "/"
            guard originalFile.hasPrefix(originalPrefix) else {
                throw OfflineLibraryError.unsafePath(file.lastPathComponent)
            }
            path = String(originalFile.dropFirst(originalPrefix.count))
        }
        _ = try self.file(path, inside: root)
        return path
    }

    static func directoryName(_ value: String, fallback: String) -> String {
        let forbidden = CharacterSet(charactersIn: "/\\:\0").union(.controlCharacters)
        let cleaned = value.components(separatedBy: forbidden).joined(separator: "_")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        var name = String(cleaned.prefix(80))
        while name.utf8.count > 100 { name.removeLast() }
        return name.isEmpty || name == "." || name == ".." || name.hasPrefix(".") ? fallback : name
    }

    static func identifierName(_ value: String) -> String {
        let name = directoryName(value, fallback: "专辑")
        guard name != value else { return name }
        // 被截断或净化的 ID 加稳定摘要，避免两张专辑被映射到同一路径。
        let digest = SHA256.hash(data: Data(value.utf8)).prefix(6).map { String(format: "%02x", $0) }.joined()
        return "\(name)-\(digest)"
    }
}
