import Foundation

extension OfflineLibraryStore {
    /// Recover the original playlist artwork retained in older download requests.
    func repairNeteasePlaylistArtwork(_ artwork: [String: URL]) async throws {
        let records = collections.filter { record in
            record.manifest.source.provider == "netease" && record.manifest.source.kind == "playlist" &&
            artwork[record.manifest.source.id] != nil && record.manifest.artworkURL != artwork[record.manifest.source.id] &&
            (record.manifest.artworkURL == nil || record.manifest.entries.contains { entry in entry.track.coverURL == record.manifest.artworkURL })
        }
        guard !records.isEmpty else { return }
        try await performImport { worker, access in
            try await worker.repairPlaylistArtwork(records, artwork: artwork, access: access)
            return nil
        }
        await scan(refreshMetadata: false)
    }
}

extension OfflineLibraryWorker {
    func repairPlaylistArtwork(_ records: [LibraryCollection], artwork: [String: URL], access: OfflineFolderAccess) throws {
        try coordinatedWrite(access.url) { root in
            for record in records {
                try Task.checkCancellation()
                guard let cover = artwork[record.manifest.source.id], ["https", "http"].contains(cover.scheme?.lowercased() ?? "") else { continue }
                let relative = try OfflinePaths.relativePath(of: record.directoryURL.appendingPathComponent(LibraryManifest.filename), inside: root)
                let file = try LocalPlaylistFile.checked(relative, root: root)
                guard (try file.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0) <= 2_000_000 else { throw OfflineLibraryError.invalidManifest }
                let current = try JSONDecoder().decode(LibraryManifest.self, from: Data(contentsOf: file))
                guard current.source == record.manifest.source else { continue }
                let updated = LibraryManifest(source: current.source, title: current.title, artist: current.artist,
                    artworkURL: cover, coverPath: current.coverPath, entries: current.entries, extra: current.extra)
                try JSONEncoder().encode(updated).write(to: file, options: .atomic)
            }
        }
    }
}
