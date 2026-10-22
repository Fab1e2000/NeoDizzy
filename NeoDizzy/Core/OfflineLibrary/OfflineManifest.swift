import Foundation
import CryptoKit

/// 附加的来源信息不参与文件标签和目录边界的判断。
nonisolated struct LibrarySource: Codable, Hashable, Sendable {
    let provider: String
    let kind: String
    let id: String
}

/// 各来源自行解释 extra；本地库只负责无损编解码。
nonisolated indirect enum LibraryJSON: Codable, Equatable, Sendable {
    case object([String: LibraryJSON]), array([LibraryJSON]), string(String), number(Decimal), bool(Bool), null

    init(from decoder: Decoder) throws {
        let value = try decoder.singleValueContainer()
        if value.decodeNil() { self = .null }
        else if let flag = try? value.decode(Bool.self) { self = .bool(flag) }
        else if let text = try? value.decode(String.self) { self = .string(text) }
        else if let number = try? value.decode(Decimal.self) { self = .number(number) }
        else if let object = try? value.decode([String: LibraryJSON].self) { self = .object(object) }
        else { self = .array(try value.decode([LibraryJSON].self)) }
    }

    func encode(to encoder: Encoder) throws {
        var value = encoder.singleValueContainer()
        switch self {
        case .object(let object): try value.encode(object)
        case .array(let array): try value.encode(array)
        case .string(let text): try value.encode(text)
        case .number(let number): try value.encode(number)
        case .bool(let flag): try value.encode(flag)
        case .null: try value.encodeNil()
        }
    }
}

/// 随音频保存的可选来源记录，不保存签名地址、cookie 或账号凭据。
nonisolated struct LibraryManifest: Codable, Sendable {
    static let filename = ".neodizzy.json"
    static let currentVersion = 2

    struct Entry: Codable, Sendable {
        let relativePath: String
        let itemID: String
        let track: Track
        let quality: String?
        var requestedQuality: String? = nil

        init(relativePath: String, itemID: String, track: Track, quality: String? = nil, requestedQuality: String? = nil) {
            self.relativePath = relativePath
            self.itemID = itemID
            self.track = track
            self.quality = quality
            self.requestedQuality = requestedQuality
        }
    }

    let version: Int
    let source: LibrarySource
    let title: String
    let artist: String
    let artworkURL: URL?
    let coverPath: String?
    private(set) var entries: [Entry]
    let extra: LibraryJSON

    init(source: LibrarySource, title: String, artist: String, artworkURL: URL? = nil,
         coverPath: String? = nil, entries: [Entry], extra: LibraryJSON = .object([:])) {
        version = Self.currentVersion
        self.source = source
        self.title = title
        self.artist = artist
        self.artworkURL = artworkURL
        self.coverPath = coverPath
        self.entries = entries
        self.extra = extra
    }

    private enum CodingKeys: String, CodingKey {
        case version, source, title, artist, artworkURL, coverPath, entries, extra
    }

    init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        let version = try values.decode(Int.self, forKey: .version)
        if version == 1 {
            self = try LegacyLibraryManifest(from: decoder).converted()
            return
        }
        self.version = version
        source = try values.decode(LibrarySource.self, forKey: .source)
        title = try values.decode(String.self, forKey: .title)
        artist = try values.decode(String.self, forKey: .artist)
        artworkURL = try values.decodeIfPresent(URL.self, forKey: .artworkURL)
        coverPath = try values.decodeIfPresent(String.self, forKey: .coverPath)
        entries = try values.decode([Entry].self, forKey: .entries)
        extra = try values.decodeIfPresent(LibraryJSON.self, forKey: .extra) ?? .object([:])
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
    func resolvingRenamedFiles(relativePaths: [String], in directory: URL) throws -> LibraryManifest {
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
            return Entry(relativePath: path, itemID: entry.itemID, track: entry.track, quality: entry.quality, requestedQuality: entry.requestedQuality)
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
        guard version == Self.currentVersion, !source.provider.isEmpty, !source.id.isEmpty,
              ["album", "playlist", "single"].contains(source.kind), !entries.isEmpty,
              Set(entries.map(\.itemID)).count == entries.count,
              Set(entries.map(\.relativePath)).count == entries.count,
              entries.allSatisfy({ !$0.itemID.isEmpty && $0.track.localSource == nil &&
                  $0.track.remoteKey == RemoteTrackKey(provider: source.provider, itemID: $0.itemID) }),
              artworkURL == nil || ["https", "http"].contains(artworkURL?.scheme?.lowercased() ?? "") else {
            throw OfflineLibraryError.invalidManifest
        }
        if source.provider == "dizzylab" {
            guard Set(entries.map { $0.track.number }).count == entries.count,
                  entries.allSatisfy({ $0.track.discID == source.id && !$0.track.number.isEmpty }) else {
                throw OfflineLibraryError.invalidManifest
            }
        }
        for entry in entries {
            _ = try OfflinePaths.file(entry.relativePath, inside: directory)
        }
        // 封面丢失不影响音频，但路径本身仍须合法。
        if let coverPath { _ = try OfflinePaths.file(coverPath, inside: directory) }
    }
}

nonisolated struct LibraryCollection: Identifiable, Codable, Sendable {
    let manifest: LibraryManifest
    let directoryURL: URL
    var id: String {
        let source = manifest.source
        return source.provider == "dizzylab" && source.kind == "album" ? source.id : "\(source.provider)/\(source.kind)/\(source.id)"
    }
    var title: String { manifest.title }
    var coverURL: URL? {
        if let path = manifest.coverPath,
           let url = try? OfflinePaths.file(path, inside: directoryURL),
           (try? url.resourceValues(forKeys: [.isRegularFileKey]).isRegularFile) == true { return url }
        return manifest.artworkURL
    }
    var tracks: [Track] {
        manifest.entries.map { entry in
            let track = entry.track
            return Track(discID: track.discID, number: track.number, title: track.title,
                         artists: track.artists, albumTitle: title, coverURL: coverURL,
                         duration: track.duration, remoteSource: track.remoteSource)
        }
    }

    func localFile(for track: Track) -> URL? {
        guard let key = track.remoteKey, key.provider == manifest.source.provider,
              (try? directoryURL.resourceValues(forKeys: [.isSymbolicLinkKey]).isSymbolicLink) == false,
              let entry = manifest.entries.first(where: { $0.itemID == key.itemID }),
              let url = try? OfflinePaths.file(entry.relativePath, inside: directoryURL),
              (try? url.resourceValues(forKeys: [.isRegularFileKey, .isSymbolicLinkKey])).map({ $0.isRegularFile == true && $0.isSymbolicLink != true }) == true else { return nil }
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
