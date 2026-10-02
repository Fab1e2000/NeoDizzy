import Foundation
import CryptoKit

/// Owns the app-private index. User music folders are always read-only.
actor LocalLibraryScanner {
    struct Result: Sendable {
        var albums: [LocalAlbum]
        var issues: [String]
    }
    private struct CachedFile: Codable {
        var metadataVersion: Int? = nil
        let trackID: String
        var albumID: String?
        var previousAlbumIDs: [String]? = nil
        var previousTrackIDs: [String]? = nil
        let size: Int
        let modified: Date?
        var metadata: AudioMetadata
        var artworkPath: String?
    }
    private struct Candidate {
        let url: URL
        let directory: URL
        let group: String
        let title: String
        let artist: String
        let disc: Int
        let number: Int?
        let fallbackTitle: String
        var cached: CachedFile
    }
    private let cacheURL: URL
    private var cache: [String: CachedFile]?
    private let readMetadata: @Sendable (URL) async throws -> AudioMetadata

    init(cacheURL: URL = URL.applicationSupportDirectory.appendingPathComponent("LocalLibrary", isDirectory: true),
         readMetadata: @escaping @Sendable (URL) async throws -> AudioMetadata = AudioMetadataReader.read) {
        self.cacheURL = cacheURL
        self.readMetadata = readMetadata
    }

    func scan(_ folders: [OfflineFolderAccess], excluding excluded: Set<String>, refreshMetadata: Bool = false, refreshPaths: Set<String> = [], managedTracks: [String: Track] = [:]) async throws -> Result {
        if cache == nil {
            cache = (try? Data(contentsOf: cacheURL.appendingPathComponent("index.json")))
                .flatMap { try? JSONDecoder().decode([String: CachedFile].self, from: $0) } ?? [:]
        }
        var index = cache ?? [:]
        var candidates: [Candidate] = []
        var issues: [String] = []
        var seen = excluded
        try FileManager.default.createDirectory(at: cacheURL, withIntermediateDirectories: true)
        // Overlapping scan roots must not duplicate the same physical file.
        for folder in folders.sorted(by: { Self.canonical($0.url) < Self.canonical($1.url) }) {
            try Task.checkCancellation()
            let files: [URL]
            do {
                let listing = try Self.files(in: folder.url)
                files = listing.files
                issues += listing.issues
            }
            catch { issues.append("\(folder.url.lastPathComponent)：\(error.localizedDescription)"); continue }
            for url in files {
                try Task.checkCancellation()
                let path = Self.canonical(url)
                guard seen.insert(path).inserted else { continue }
                do {
                    _ = try OfflinePaths.relativePath(of: url, inside: folder.url)
                    let values = try url.resourceValues(forKeys: [.fileSizeKey, .contentModificationDateKey])
                    var record: CachedFile
                    if !refreshMetadata, !refreshPaths.contains(path), let cached = index[path], cached.metadataVersion == 4, cached.size == values.fileSize, cached.modified == values.contentModificationDate,
                       cached.artworkPath == nil || FileManager.default.fileExists(atPath: cacheURL.appendingPathComponent(cached.artworkPath!).path) {
                        record = cached
                    } else {
                        var metadata: AudioMetadata
                        do {
                            metadata = try await readMetadata(url)
                        } catch is CancellationError { throw CancellationError() }
                        catch {
                            // Managed imports already passed validation. Preserve their
                            // known playback entry if a provider cannot read tags now.
                            // A tag-save refresh must verify the actual new metadata,
                            // not report success with the old download manifest.
                            guard !refreshPaths.contains(path), managedTracks[path] != nil else { throw error }
                            metadata = AudioMetadata()
                            issues.append("\(url.lastPathComponent)：标签读取失败，暂用下载信息（\(error.localizedDescription)）")
                        }
                        if let track = managedTracks[path] {
                            if metadata.title.isEmpty { metadata.title = track.title }
                            if metadata.album.isEmpty { metadata.album = track.albumTitle }
                            if metadata.artist.isEmpty { metadata.artist = track.artists }
                            if metadata.trackNumber == nil { metadata.trackNumber = Int(track.number) }
                            if metadata.duration == nil { metadata.duration = track.duration }
                        }
                        let trackID = index[path]?.trackID ?? UUID().uuidString
                        var artworkPath: String?
                        if let artwork = metadata.artwork {
                            let digest = SHA256.hash(data: artwork).map { String(format: "%02x", $0) }.joined()
                            artworkPath = "\(trackID)-\(digest).artwork"
                            try artwork.write(to: cacheURL.appendingPathComponent(artworkPath!), options: .atomic)
                        }
                        metadata.artwork = nil
                        record = CachedFile(metadataVersion: 4, trackID: trackID, albumID: index[path]?.albumID,
                                            previousAlbumIDs: index[path]?.previousAlbumIDs, previousTrackIDs: index[path]?.previousTrackIDs, size: values.fileSize ?? 0, modified: values.contentModificationDate,
                                            metadata: metadata, artworkPath: artworkPath)
                    }
                    index[path] = record
                    let metadata = record.metadata
                    let directory = url.deletingLastPathComponent()
                    let discFolder = Self.discNumber(directory.lastPathComponent)
                    // The immediate containing directory is the only album boundary.
                    let title = directory.lastPathComponent
                    let artist = metadata.albumArtist
                    let key = Self.canonical(directory)
                    let fallback = Self.filename(url.deletingPathExtension().lastPathComponent)
                    candidates.append(Candidate(url: url, directory: directory, group: key, title: title, artist: artist,
                                                disc: metadata.discNumber ?? discFolder ?? 1,
                                                number: metadata.trackNumber ?? fallback.number,
                                                fallbackTitle: fallback.title, cached: record))
                } catch is CancellationError { throw CancellationError() }
                catch { issues.append("\(url.lastPathComponent)：\(error.localizedDescription)") }
            }
        }
        var albums: [LocalAlbum] = []
        var usedAlbumIDs = Set<String>()
        let groups = Dictionary(grouping: candidates, by: \.group)
        for key in groups.keys.sorted() {
            try Task.checkCancellation()
            let files = groups[key]!.sorted {
                if $0.disc != $1.disc { return $0.disc < $1.disc }
                if $0.number != $1.number { return ($0.number ?? Int.max) < ($1.number ?? Int.max) }
                return $0.url.path.localizedStandardCompare($1.url.path) == .orderedAscending
            }
            guard let first = files.first else { continue }
            // Recover identity from file membership, not title, tags or track numbers.
            let albumID = files.compactMap(\.cached.albumID).first { !usedAlbumIDs.contains($0) } ?? UUID().uuidString
            usedAlbumIDs.insert(albumID)
            let previousIDs = Set(files.flatMap { ($0.cached.previousAlbumIDs ?? []) + [$0.cached.albumID].compactMap { $0 } }).subtracting([albumID])
            let embedded = files.compactMap(\.cached.artworkPath).first.map { cacheURL.appendingPathComponent($0) }
            let cover = embedded ?? Self.cover(in: first.directory) ?? managedTracks[Self.canonical(first.url)]?.coverURL
            let albumArtists = files.map(\.artist).filter { !$0.isEmpty }
            let credits = albumArtists.isEmpty ? files.map(\.cached.metadata.artist).filter { !$0.isEmpty } : albumArtists
            var artists: [String] = []
            for credit in credits where !artists.contains(credit) { artists.append(credit) }
            let artist = artists.isEmpty ? "未知艺术家" : artists.joined(separator: " / ")
            let entries = files.enumerated().map { offset, file in
                var record = file.cached
                record.albumID = albumID
                record.previousAlbumIDs = previousIDs.sorted()
                record.previousTrackIDs = nil
                index[Self.canonical(file.url)] = record
                let metadata = record.metadata
                let track = Track(discID: managedTracks[Self.canonical(file.url)]?.discID ?? "", number: managedTracks[Self.canonical(file.url)]?.number ?? String(file.number ?? offset + 1),
                                  title: metadata.title.isEmpty ? file.fallbackTitle : metadata.title,
                                  artists: metadata.artist.isEmpty ? "未知艺术家" : metadata.artist,
                                  albumTitle: first.title, coverURL: cover, duration: metadata.duration,
                                  // Every visible file has its own identity, including
                                  // copies of the same downloaded site track.
                                  localSource: LocalTrackSource(albumID: albumID, trackID: record.trackID))
                return LocalAlbum.Entry(track: track, fileURL: file.url, discNumber: file.disc, previousTrackIDs: Set(record.previousTrackIDs ?? []))
            }
            albums.append(LocalAlbum(id: albumID, title: first.title, artist: artist, coverURL: cover, entries: entries, previousIDs: previousIDs))
        }
        // A formerly merged ID must not shadow a currently visible folder album.
        let currentIDs = Set(albums.map(\.id))
        albums = albums.map { album in
            var album = album
            album.previousIDs.subtract(currentIDs)
            for entry in album.entries {
                index[Self.canonical(entry.fileURL)]?.previousAlbumIDs = album.previousIDs.sorted()
            }
            return album
        }
        try Task.checkCancellation()
        cache = index
        try JSONEncoder().encode(index).write(to: cacheURL.appendingPathComponent("index.json"), options: .atomic)
        return Result(albums: albums.sorted { $0.title.localizedStandardCompare($1.title) == .orderedAscending }, issues: issues)
    }

    nonisolated static func canonical(_ url: URL) -> String { url.standardizedFileURL.resolvingSymlinksInPath().path }

    nonisolated struct FileListing {
        var files: [URL]
        var issues: [String]
    }

    nonisolated static func files(in root: URL) throws -> FileListing {
        var result: Swift.Result<FileListing, Error>?
        var coordinationError: NSError?
        NSFileCoordinator().coordinate(readingItemAt: root, options: [], error: &coordinationError) { directory in
            result = Swift.Result {
                guard try directory.resourceValues(forKeys: [.isDirectoryKey, .isSymbolicLinkKey]).isDirectory == true,
                      try directory.resourceValues(forKeys: [.isSymbolicLinkKey]).isSymbolicLink != true else {
                    throw OfflineLibraryError.invalidFolder
                }
                var issues: [String] = []
                guard let enumerator = FileManager.default.enumerator(at: directory,
                    includingPropertiesForKeys: [.isSymbolicLinkKey, .isRegularFileKey],
                    options: [.skipsHiddenFiles, .skipsPackageDescendants], errorHandler: { url, error in
                        issues.append("\(url.lastPathComponent)：\(error.localizedDescription)")
                        return true
                    }) else { throw OfflineLibraryError.invalidFolder }
                var files: [URL] = []
                for case let file as URL in enumerator {
                    try Task.checkCancellation()
                    do {
                        let values = try file.resourceValues(forKeys: [.isSymbolicLinkKey, .isRegularFileKey])
                        if values.isSymbolicLink == true || file.lastPathComponent == "__MACOSX" {
                            enumerator.skipDescendants(); continue
                        }
                        if values.isRegularFile == true, AudioFileMatcher.extensions.contains(file.pathExtension.lowercased()) {
                            files.append(file)
                        }
                    } catch { issues.append("\(file.lastPathComponent)：\(error.localizedDescription)") }
                }
                return FileListing(files: files.sorted { $0.path < $1.path }, issues: issues)
            }
        }
        if let coordinationError { throw coordinationError }
        return try result?.get() ?? FileListing(files: [], issues: [])
    }

    nonisolated private static func cover(in directory: URL) -> URL? {
        let names = ["cover", "folder"]
        let images = (try? FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: [.isRegularFileKey, .isSymbolicLinkKey])) ?? []
        return images.filter { url in
            names.contains(url.deletingPathExtension().lastPathComponent.lowercased()) &&
            ["jpg", "jpeg", "png", "heic"].contains(url.pathExtension.lowercased()) &&
            (try? url.resourceValues(forKeys: [.isSymbolicLinkKey]).isSymbolicLink) == false &&
            (try? url.resourceValues(forKeys: [.isRegularFileKey]).isRegularFile) == true
        }.sorted { $0.lastPathComponent < $1.lastPathComponent }.first
    }

    nonisolated static func discNumber(_ name: String) -> Int? {
        guard let range = name.range(of: "^(?:cd|disc|disk)[ _.-]*([0-9]+)$", options: [.regularExpression, .caseInsensitive]) else { return nil }
        return Int(name[range].filter(\.isNumber))
    }

    nonisolated static func filename(_ name: String) -> (number: Int?, title: String) {
        let normalized = name.folding(options: [.widthInsensitive], locale: Locale(identifier: "en_US_POSIX"))
        let regex = try! NSRegularExpression(pattern: "^(?:track[ _.-]*)?([0-9]{1,4})[\\s._\\-、．:：)）\\]]+(.*)$", options: [.caseInsensitive])
        guard let match = regex.firstMatch(in: normalized, range: NSRange(normalized.startIndex..., in: normalized)),
              let number = Range(match.range(at: 1), in: normalized), let title = Range(match.range(at: 2), in: normalized),
              !normalized[title].isEmpty else { return (nil, name) }
        return (Int(normalized[number]), String(normalized[title]))
    }
}
