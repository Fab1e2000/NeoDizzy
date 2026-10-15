import Foundation

extension OfflineLibraryWorker {
    nonisolated static func hasLegacyNeteaseName(_ album: LibraryCollection) -> Bool {
        let manifest = album.manifest
        guard manifest.source.provider == "netease", manifest.source.kind == "album" else { return false }
        let old = OfflinePaths.directoryName("\(manifest.artist) - \(manifest.title)", fallback: manifest.source.id)
        let new = OfflinePaths.directoryName(manifest.title, fallback: manifest.source.id)
        return old != new && album.directoryURL.lastPathComponent == old
    }

    /// Rename only the exact managed name emitted by the old downloader; preserve custom names.
    /// A move keeps audio bytes and file identities intact. M3U references move with the directory.
    nonisolated static func migrateNeteaseAlbumNames(_ albums: [LibraryCollection], in root: URL) throws -> Bool {
        let manager = FileManager.default
        var changed = false
        for album in albums where hasLegacyNeteaseName(album) {
            try Task.checkCancellation()
            let oldPath = try OfflinePaths.relativePath(of: album.directoryURL, inside: root)
            let source = try LocalPlaylistFile.checked(oldPath, root: root)
            let name = OfflinePaths.directoryName(album.manifest.title, fallback: album.manifest.source.id)
            let destination = source.deletingLastPathComponent().appendingPathComponent(name, isDirectory: true)
            let newPath = try OfflinePaths.relativePath(of: destination, inside: root)
            _ = try LocalPlaylistFile.checked(newPath, root: root)
            // Never merge or overwrite a different album with the same title.
            guard !manager.fileExists(atPath: destination.path) else { continue }
            try album.manifest.validate(in: source)

            var edits: [(url: URL, original: Data, updated: Data)] = []
            let playlists = try LocalPlaylistFile.checked("Playlists", root: root)
            if manager.fileExists(atPath: playlists.path) {
                for file in try manager.contentsOfDirectory(at: playlists, includingPropertiesForKeys: nil)
                    where file.pathExtension.lowercased() == "m3u8" {
                    let url = try LocalPlaylistFile.checked("Playlists/" + file.lastPathComponent, root: root)
                    guard (try url.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0) <= 4 * 1_024 * 1_024 else { continue }
                    let original = try Data(contentsOf: url)
                    guard let text = String(data: original, encoding: .utf8) else { continue }
                    var modified = false
                    let lines = text.components(separatedBy: .newlines).map { line -> String in
                        guard !line.isEmpty, !line.hasPrefix("#"),
                              let audio = try? LocalPlaylistFile.resolve(line, root: root),
                              let relative = try? OfflinePaths.relativePath(of: audio, inside: source) else { return line }
                        modified = true
                        return "../\(newPath)/\(relative)"
                    }
                    if modified { edits.append((url, original, Data(lines.joined(separator: "\n").utf8))) }
                }
            }
            try manager.moveItem(at: source, to: destination)
            var written: [(url: URL, original: Data)] = []
            do {
                for edit in edits {
                    try edit.updated.write(to: edit.url, options: .atomic)
                    written.append((edit.url, edit.original))
                }
            } catch {
                for edit in written.reversed() { try? edit.original.write(to: edit.url, options: .atomic) }
                try manager.moveItem(at: destination, to: source)
                throw error
            }
            changed = true
        }
        return changed
    }
}
