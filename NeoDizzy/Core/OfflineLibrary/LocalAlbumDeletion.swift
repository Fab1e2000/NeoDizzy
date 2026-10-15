import Foundation

extension OfflineLibraryStore {
    func deleteAlbum(_ album: LocalAlbum) async throws {
        try await deleteAlbums(ids: [album.id])
    }

    func deleteAlbums(ids: Set<String>) async throws {
        // Resolve the current index again: a menu may outlive a refresh or folder change.
        let entries = ids.compactMap { localAlbum(id: $0) }.flatMap(\.entries)
        guard !entries.isEmpty else { return }
        let paths = Set(entries.map { LocalLibraryScanner.canonical($0.fileURL) })
        let manifests = collections.filter { collection in
            collection.manifest.entries.contains { entry in
                guard let file = try? OfflinePaths.file(entry.relativePath, inside: collection.directoryURL) else { return false }
                return paths.contains(LocalLibraryScanner.canonical(file))
            }
        }.map { $0.directoryURL.appendingPathComponent(LibraryManifest.filename) }
        do {
            try await performImport { worker, access in
                try await worker.deleteAlbumFiles(entries.map(\.fileURL), access: access, manifests: manifests)
                return nil
            }
        } catch {
            // A filesystem error can occur after some files were removed.
            await scan(refreshMetadata: false)
            throw error
        }
        await scan(refreshMetadata: false)
    }
}

extension OfflineLibraryWorker {
    func deleteAlbumFiles(_ files: [URL], access: OfflineFolderAccess, manifests: [URL] = []) throws {
        try coordinatedWrite(access.url) { root in
            let rootPath = root.standardizedFileURL.resolvingSymlinksInPath().path
            // Validate every entry before removing anything. Never delete a whole directory:
            // albums can share folders with other albums, nested discs, artwork or documents.
            let targets = try Set(files).map { file -> URL in
                var ancestor = file
                while true {
                    guard (try? ancestor.resourceValues(forKeys: [.isSymbolicLinkKey]).isSymbolicLink) != true else {
                        throw OfflineLibraryError.unsafePath(file.path)
                    }
                    if ancestor.standardizedFileURL.resolvingSymlinksInPath().path == rootPath { break }
                    guard ancestor.path != "/" else { throw OfflineLibraryError.unsafePath(file.path) }
                    ancestor.deleteLastPathComponent()
                }
                let relative = try OfflinePaths.relativePath(of: file, inside: root)
                let target = try LocalPlaylistFile.checked(relative, root: root)
                guard AudioFileMatcher.extensions.contains(target.pathExtension.lowercased()),
                      try target.resourceValues(forKeys: [.isRegularFileKey]).isRegularFile == true else {
                    throw OfflineLibraryError.unsafePath(relative)
                }
                return target
            }
            var removed = Set<String>()
            do {
                for target in targets {
                    try Task.checkCancellation()
                    try FileManager.default.removeItem(at: target)
                    removed.insert(LocalLibraryScanner.canonical(target))
                }
            } catch {
                try? Self.removeDeletedReferences(removed, manifests: manifests, root: root)
                throw error
            }
            try Self.removeDeletedReferences(removed, manifests: manifests, root: root)
        }
    }
}


extension OfflineLibraryWorker {
    /// Only rewrite references to files explicitly deleted by this operation.
    nonisolated private static func removeDeletedReferences(_ removed: Set<String>, manifests: [URL], root: URL) throws {
        guard !removed.isEmpty else { return }
        for file in manifests {
            let relative = try OfflinePaths.relativePath(of: file, inside: root)
            let url = try LocalPlaylistFile.checked(relative, root: root)
            guard FileManager.default.fileExists(atPath: url.path) else { continue }
            guard (try url.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0) <= 2_000_000 else {
                throw OfflineLibraryError.invalidManifest
            }
            let manifest = try JSONDecoder().decode(LibraryManifest.self, from: Data(contentsOf: url))
            let retained = try manifest.entries.filter {
                let audio = try OfflinePaths.file($0.relativePath, inside: url.deletingLastPathComponent())
                return !removed.contains(LocalLibraryScanner.canonical(audio))
            }
            guard retained.count != manifest.entries.count else { continue }
            if retained.isEmpty { try FileManager.default.removeItem(at: url) }
            else {
                let updated = LibraryManifest(source: manifest.source, title: manifest.title, artist: manifest.artist,
                                              artworkURL: manifest.artworkURL, coverPath: manifest.coverPath,
                                              entries: retained, extra: manifest.extra)
                try JSONEncoder().encode(updated).write(to: url, options: .atomic)
            }
        }
        let directory = try LocalPlaylistFile.checked("Playlists", root: root)
        guard FileManager.default.fileExists(atPath: directory.path) else { return }
        for file in try FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)
            where file.pathExtension.lowercased() == "m3u8" {
            let url = try LocalPlaylistFile.checked("Playlists/" + file.lastPathComponent, root: root)
            guard (try url.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0) <= 4 * 1_024 * 1_024 else { continue }
            let original = try String(contentsOf: url, encoding: .utf8)
            var lines: [String] = []
            var changed = false
            for line in original.components(separatedBy: .newlines) {
                if !line.isEmpty, !line.hasPrefix("#"),
                   let audio = try? LocalPlaylistFile.resolve(line, root: root),
                   removed.contains(LocalLibraryScanner.canonical(audio)) {
                    if lines.last?.hasPrefix("#EXTINF:") == true { lines.removeLast() }
                    changed = true
                } else { lines.append(line) }
            }
            if changed { try Data(lines.joined(separator: "\n").utf8).write(to: url, options: .atomic) }
        }
    }
}
