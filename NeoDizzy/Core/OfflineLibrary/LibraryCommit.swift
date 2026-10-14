import Foundation

nonisolated enum LibraryProvenance: Sendable {
    case collection(LibraryManifest, merge: Bool, preserving: [String], placeholderMarker: String?)
    case attachment(LibrarySource, subdirectory: String, marker: String)
}

extension OfflineLibraryStore {
    func commit(staging: URL, folderName: String, provenance: LibraryProvenance) async throws {
        try await performImport { worker, folder in
            try await worker.commit(staging: staging, folderName: folderName, provenance: provenance, into: folder)
        }
    }
}

extension OfflineLibraryWorker {
    func commit(staging: URL, folderName: String, provenance: LibraryProvenance, into folder: OfflineFolderAccess) throws -> LibraryCollection? {
        try coordinatedWrite(folder.url) { root in
            try Self.commitDirectory(staging: staging, folderName: folderName, provenance: provenance, into: root)
        }
    }

    nonisolated static func commitDirectory(staging source: URL, folderName: String, provenance: LibraryProvenance, into root: URL) throws -> LibraryCollection? {
        let fm = FileManager.default
        let target = try folderName.isEmpty ? root : OfflinePaths.file(folderName, inside: root)
        // 所有父目录都拒绝符号链接，包括指向库内的链接。
        var parent = root
        for component in folderName.split(separator: "/") {
            parent.appendPathComponent(String(component))
            guard (try? parent.resourceValues(forKeys: [.isSymbolicLinkKey]).isSymbolicLink) != true else { throw OfflineLibraryError.unsafePath(folderName) }
        }
        let paths = try extractedFiles(in: source)
        try fm.createDirectory(at: target.deletingLastPathComponent(), withIntermediateDirectories: true)
        let temporary = (folderName.isEmpty ? root : target.deletingLastPathComponent()).appendingPathComponent(".neodizzy-import-\(UUID())")
        try fm.createDirectory(at: temporary, withIntermediateDirectories: false)
        defer { try? fm.removeItem(at: temporary) }
        let exists = fm.fileExists(atPath: target.path)
        func copy(_ paths: [String], from origin: URL, to destination: URL) throws {
            for path in paths where URL(fileURLWithPath: path).lastPathComponent != LibraryManifest.filename {
                try Task.checkCancellation()
                let file = try OfflinePaths.file(path, inside: destination)
                try fm.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
                try fm.copyItem(at: OfflinePaths.file(path, inside: origin), to: file)
            }
        }
        func markerMatches(_ directory: URL, _ marker: String, _ id: String) -> Bool {
            guard let url = try? OfflinePaths.file(marker, inside: directory) else { return false }
            return (try? String(contentsOf: url, encoding: .utf8)) == id
        }
        switch provenance {
        case .collection(let incoming, let merge, let preserving, let marker):
            guard !folderName.isEmpty else { throw OfflineLibraryError.unsafePath(folderName) }
            try incoming.validate(in: source)
            var manifest = incoming
            var legacyURL: URL?
            var incomingPaths = paths
            if exists {
                let manifestURL = try OfflinePaths.file(LibraryManifest.filename, inside: target)
                if fm.fileExists(atPath: manifestURL.path) {
                    let data = try Data(contentsOf: manifestURL)
                    let previous = try JSONDecoder().decode(LibraryManifest.self, from: data)
                    guard previous.source == incoming.source else { throw OfflineLibraryError.existingAlbum }
                    if (try JSONSerialization.jsonObject(with: data) as? [String: Any])?["version"] as? Int == 1 {
                        guard !merge else { throw OfflineLibraryError.existingAlbum }
                        legacyURL = manifestURL
                        manifest = previous
                    } else if merge {
                        try previous.validate(in: target)
                        let known = Set(previous.entries.map(\.itemID))
                        let added = incoming.entries.filter { !known.contains($0.itemID) }
                        let oldPaths = try extractedFiles(in: target)
                        let occupied = Set(oldPaths)
                        guard added.allSatisfy({ !occupied.contains($0.relativePath) }) else { throw OfflineLibraryError.existingAlbum }
                        let skipped = Set(incoming.entries.filter { known.contains($0.itemID) }.map(\.relativePath))
                        incomingPaths = paths.filter { !skipped.contains($0) && !occupied.contains($0) }
                        try copy(oldPaths, from: target, to: temporary)
                        manifest = LibraryManifest(source: previous.source, title: previous.title, artist: previous.artist,
                            artworkURL: previous.artworkURL, coverPath: previous.coverPath,
                            entries: previous.entries + added, extra: previous.extra)
                    }
                } else {
                    guard let marker, markerMatches(target, marker, incoming.source.id),
                          Set(try fm.contentsOfDirectory(atPath: target.path)) == Set(preserving + [marker]) else { throw OfflineLibraryError.existingAlbum }
                }
            }
            try copy(incomingPaths, from: source, to: temporary)
            if exists && !merge {
                for path in preserving where fm.fileExists(atPath: target.appendingPathComponent(path).path) {
                    let old = try OfflinePaths.file(path, inside: target)
                    _ = try extractedFiles(in: old)
                    try fm.copyItem(at: old, to: OfflinePaths.file(path, inside: temporary))
                }
            }
            let manifestURL = temporary.appendingPathComponent(LibraryManifest.filename)
            if let legacyURL { try fm.linkItem(at: legacyURL, to: manifestURL) }
            else {
                let encoder = JSONEncoder(); encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
                try encoder.encode(manifest).write(to: manifestURL, options: .atomic)
            }
            try manifest.validate(in: temporary)
            try Task.checkCancellation()
            if exists { try commit(temporary, replacing: target) }
            else { try fm.moveItem(at: temporary, to: target) }
            return LibraryCollection(manifest: manifest, directoryURL: target)
        case .attachment(let collection, let subdirectory, let marker):
            guard !paths.isEmpty else { throw DownloadFailure.damagedArchive }
            if exists {
                let manifestURL = try OfflinePaths.file(LibraryManifest.filename, inside: target)
                if fm.fileExists(atPath: manifestURL.path) {
                    let manifest = try JSONDecoder().decode(LibraryManifest.self, from: Data(contentsOf: manifestURL))
                    guard manifest.source == collection else { throw OfflineLibraryError.existingAlbum }
                    try manifest.validate(in: target)
                } else {
                    guard markerMatches(target, marker, collection.id),
                          Set(try fm.contentsOfDirectory(atPath: target.path)) == Set([subdirectory, marker]) else { throw OfflineLibraryError.existingAlbum }
                }
            }
            let contents = try OfflinePaths.file(subdirectory, inside: temporary)
            try fm.createDirectory(at: contents, withIntermediateDirectories: true)
            try copy(paths, from: source, to: contents)
            try collection.id.write(to: OfflinePaths.file(marker, inside: contents), atomically: true, encoding: .utf8)
            try Task.checkCancellation()
            if exists {
                let destination = try OfflinePaths.file(subdirectory, inside: target)
                if fm.fileExists(atPath: destination.path) {
                    guard markerMatches(destination, marker, collection.id) else { throw OfflineLibraryError.existingAlbum }
                    try commit(contents, replacing: destination)
                } else { try fm.moveItem(at: contents, to: destination) }
            } else {
                try collection.id.write(to: OfflinePaths.file(marker, inside: temporary), atomically: true, encoding: .utf8)
                try fm.moveItem(at: temporary, to: target)
            }
            return nil
        }
    }
}
