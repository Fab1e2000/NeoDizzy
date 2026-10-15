import Foundation

nonisolated struct LocalPlaylist: Identifiable, Sendable {
    var id: String { fileURL.standardizedFileURL.path }
    let fileURL: URL
    let title: String
    let tracks: [Track]
    let source: LibrarySource?
    var artworkURL: URL? = nil
    var coverURL: URL? { artworkURL ?? tracks.first?.coverURL }
}

/// 歌单只保存引用；所有路径先按根目录归一化，再沿途拒绝符号链接。
nonisolated enum LocalPlaylistFile {
    static func checked(_ path: String, root: URL) throws -> URL {
        let url = try OfflinePaths.file(path, inside: root)
        var current = root
        for part in path.split(separator: "/") {
            current.appendPathComponent(String(part))
            if (try? current.resourceValues(forKeys: [.isSymbolicLinkKey]).isSymbolicLink) == true {
                throw OfflineLibraryError.unsafePath(path)
            }
        }
        return url
    }

    static func resolve(_ line: String, root: URL) throws -> URL {
        guard !line.hasPrefix("/"), !line.contains(":"), !line.contains("\\"), !line.contains("\0") else {
            throw OfflineLibraryError.unsafePath(line)
        }
        var parts = ["Playlists"]
        for part in line.split(separator: "/") {
            if part == "." { continue }
            if part == ".." {
                guard !parts.isEmpty else { throw OfflineLibraryError.unsafePath(line) }
                parts.removeLast()
            } else { parts.append(String(part)) }
        }
        return try checked(parts.joined(separator: "/"), root: root)
    }

    static func read(_ url: URL, root: URL, tracks: [String: Track]) throws -> (LocalPlaylist, [String]) {
        guard (try? url.resourceValues(forKeys: [.isSymbolicLinkKey]).isSymbolicLink) != true else {
            throw OfflineLibraryError.unsafePath(url.lastPathComponent)
        }
        let path = try OfflinePaths.relativePath(of: url, inside: root)
        let file = try checked(path, root: root)
        guard try file.resourceValues(forKeys: [.fileSizeKey, .isRegularFileKey]).isRegularFile == true,
              (try file.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0) <= 4 * 1_024 * 1_024 else {
            throw OfflineLibraryError.invalidFolder
        }
        let text = try String(contentsOf: file, encoding: .utf8)
        var entries: [Track] = []
        var issues: [String] = []
        var source: LibrarySource?
        for raw in text.components(separatedBy: .newlines) {
            let line = raw.replacingOccurrences(of: "\u{FEFF}", with: "")
            if line.hasPrefix("#NEODIZZY-SOURCE:") {
                let parts = line.split(separator: ":", omittingEmptySubsequences: false)
                if parts.count == 4, parts[1] == "netease", parts[2] == "playlist", !parts[3].isEmpty {
                    source = LibrarySource(provider: String(parts[1]), kind: String(parts[2]), id: String(parts[3]))
                }
            }
            guard !line.isEmpty, !line.hasPrefix("#") else { continue }
            do {
                let audio = try resolve(line, root: root)
                // Deleted local audio is no longer a playlist item, not a persistent library warning.
                guard FileManager.default.fileExists(atPath: audio.path) else { continue }
                guard let track = tracks[LocalLibraryScanner.canonical(audio)] else {
                    throw OfflineLibraryError.unsafePath(line)
                }
                entries.append(track)
            } catch { issues.append("\(url.lastPathComponent)：无法读取引用 \(line)") }
        }
        return (LocalPlaylist(fileURL: file, title: file.deletingPathExtension().lastPathComponent, tracks: entries, source: source), issues)
    }

    static func write(title: String, entries: [(Track, URL)], source: LibrarySource?, existing: URL?, root: URL) throws {
        let directory = try checked("Playlists", root: root)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let name = OfflinePaths.directoryName(title, fallback: "新歌单") + ".m3u8"
        let path = try existing.map { try OfflinePaths.relativePath(of: $0, inside: root) } ?? "Playlists/\(name)"
        guard path.split(separator: "/").count == 2, path.hasPrefix("Playlists/"), path.hasSuffix(".m3u8") else {
            throw OfflineLibraryError.unsafePath(path)
        }
        let target = try checked(path, root: root)
        if existing == nil, FileManager.default.fileExists(atPath: target.path) { throw OfflineLibraryError.existingAlbum }
        var lines = ["#EXTM3U"]
        if let source {
            guard source.provider == "netease", source.kind == "playlist", !source.id.isEmpty,
                  !source.id.contains(where: { $0 == ":" || $0.isNewline }) else { throw OfflineLibraryError.invalidFolder }
            lines.append("#NEODIZZY-SOURCE:\(source.provider):\(source.kind):\(source.id)")
        }
        for (track, file) in entries {
            let relative = try OfflinePaths.relativePath(of: file, inside: root)
            _ = try checked(relative, root: root)
            guard !relative.contains(where: \.isNewline), !relative.contains(":"), FileManager.default.fileExists(atPath: file.path) else {
                throw OfflineLibraryError.unsafePath(relative)
            }
            let label = track.title.components(separatedBy: .newlines).joined(separator: " ")
            lines.append("#EXTINF:\(Int(track.duration ?? -1)),\(label)")
            lines.append("../\(relative)")
        }
        try Data((lines.joined(separator: "\n") + "\n").utf8).write(to: target, options: .atomic)
    }
}

extension OfflineLibraryStore {
    func savePlaylist(title: String, tracks: [Track], source: LibrarySource? = nil, existing: LocalPlaylist? = nil) async throws {
        let entries = try tracks.map { track in
            guard let file = localFile(for: track) else { throw OfflineLibraryError.invalidFolder }
            return (track, file)
        }
        let previous = existing ?? source.flatMap { value in localPlaylists.first { $0.source == value } }
        try await performImport { worker, access in
            try await worker.writePlaylist(title: title, entries: entries, source: source ?? previous?.source, existing: previous?.fileURL.pathExtension == "m3u8" ? previous?.fileURL : nil, access: access)
            return nil
        }
        await scan(refreshMetadata: false)
    }

    func add(_ track: Track, to playlist: LocalPlaylist) async throws {
        let tracks = playlist.tracks.contains(where: { $0.id == track.id }) ? playlist.tracks : playlist.tracks + [track]
        try await savePlaylist(title: playlist.title, tracks: tracks, existing: playlist)
    }

    func deletePlaylist(_ playlist: LocalPlaylist) async throws {
        if let source = playlist.source,
           let record = collection(provider: source.provider, kind: source.kind, id: source.id) {
            let directory = LocalLibraryScanner.canonical(record.directoryURL)
            let ids = Set(localAlbums.filter { $0.entries.contains { LocalLibraryScanner.canonical($0.fileURL.deletingLastPathComponent()) == directory } }.map(\.id))
            try await deleteAlbums(ids: ids)
        }
        guard playlist.fileURL.pathExtension == "m3u8" else { return }
        try await performImport { worker, access in
            try await worker.deletePlaylist(playlist.fileURL, access: access)
            return nil
        }
        await scan(refreshMetadata: false)
    }

    func sourceLabel(for album: LocalAlbum) -> String? {
        let paths = Set(album.entries.map { LocalLibraryScanner.canonical($0.fileURL.deletingLastPathComponent()) })
        let providers = Set(collections.filter { paths.contains(LocalLibraryScanner.canonical($0.directoryURL)) }.map { $0.manifest.source.provider })
        let label = providers.sorted().map { $0 == "netease" ? "网易云" : $0 == "dizzylab" ? "DizzyLab" : $0 }.joined(separator: " · ")
        return label.isEmpty ? nil : label
    }
}

extension OfflineLibraryWorker {
    func writePlaylist(title: String, entries: [(Track, URL)], source: LibrarySource?, existing: URL?, access: OfflineFolderAccess) throws {
        try coordinatedWrite(access.url) { root in
            try LocalPlaylistFile.write(title: title, entries: entries, source: source, existing: existing, root: root)
        }
    }
    func deletePlaylist(_ url: URL, access: OfflineFolderAccess) throws {
        try coordinatedWrite(access.url) { root in
            let path = try OfflinePaths.relativePath(of: url, inside: root)
            guard path.hasPrefix("Playlists/"), path.split(separator: "/").count == 2, path.hasSuffix(".m3u8") else {
                throw OfflineLibraryError.unsafePath(path)
            }
            try FileManager.default.removeItem(at: LocalPlaylistFile.checked(path, root: root))
        }
    }
}
