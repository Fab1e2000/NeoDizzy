import Foundation

extension QQMusicError: DownloadDisplayableError {}

nonisolated struct QQMusicDownloadRequest: Codable {
    let kind: String
    let id: String
    let quality: QQMusicQuality
}

/// Stable metadata only. Resolved addresses, credentials and account scopes stay in memory.
nonisolated struct QQMusicDownloadMetadata: Codable {
    var transferID = UUID()
    let track: Track
    let trackNumber: Int
    let discNumber: Int
    let quality: QQMusicQuality
    var actualQuality: String?
    var type: String?
    var playlistID: String?
    var playlistTitle: String?
    var playlistPosition: Int?
    var playlistArtworkURL: URL?
}

nonisolated enum QQMusicDownloadError: DownloadDisplayableError {
    case sessionChanged, invalidAudio
    var errorDescription: String? {
        switch self {
        case .sessionChanged: "QQ 音乐账号已变化，请重试下载。"
        case .invalidAudio: "下载的音频格式无法识别，请重试。"
        }
    }
}

@MainActor final class QQMusicDownloadProvider: DownloadProvider {
    let id = "qqmusic"
    private let api: QQMusicClient
    private let library: OfflineLibraryStore
    private let artworkSession: URLSession
    private let cacheScope: () -> String?
    private let sessionRevision: () -> Int
    private struct Context: Equatable { let scope: String; let revision: Int }
    private var contexts: [UUID: Context] = [:]

    init(api: QQMusicClient, library: OfflineLibraryStore, artworkSession: URLSession = .shared,
         cacheScope: @escaping () -> String?, sessionRevision: @escaping () -> Int = { 0 }) {
        self.api = api; self.library = library; self.artworkSession = artworkSession
        self.cacheScope = cacheScope; self.sessionRevision = sessionRevision
    }
    private func context() throws -> Context {
        try Task.checkCancellation()
        guard let scope = cacheScope() else { throw QQMusicDownloadError.sessionChanged }
        return Context(scope: scope, revision: sessionRevision())
    }
    private func check(_ captured: Context) throws {
        guard try context() == captured else { throw QQMusicDownloadError.sessionChanged }
    }
    func title(_ data: Data) -> String { (try? JSONDecoder().decode(DownloadRequest.self, from: data).title) ?? "下载歌曲" }
    func identity(_ data: Data) -> String { (try? JSONDecoder().decode(DownloadRequest.self, from: data).identity) ?? "" }
    func summary(for transfer: DownloadTransfer) -> DownloadTransferSummary? {
        guard let metadata = try? JSONDecoder().decode(QQMusicDownloadMetadata.self, from: transfer.metadata) else { return nil }
        return .init(title: metadata.track.title, subtitle: metadata.track.artists)
    }

    func plan(_ data: Data) async throws -> [DownloadTransfer] {
        let captured = try context()
        let envelope = try JSONDecoder().decode(DownloadRequest.self, from: data)
        let request = try JSONDecoder().decode(QQMusicDownloadRequest.self, from: envelope.payload)
        let songs: [QQMusicSong]
        var artwork = envelope.coverURL
        switch request.kind {
        case "single": songs = [try await api.song(mid: request.id)]
        case "album":
            let received = try await api.album(mid: request.id).songs
            songs = received.enumerated().sorted {
                ($0.element.discNumber ?? 1, $0.element.trackNumber ?? Int.max, $0.offset) <
                ($1.element.discNumber ?? 1, $1.element.trackNumber ?? Int.max, $1.offset)
            }.map(\.element)
        case "playlist":
            let collection = try await api.playlist(id: request.id)
            songs = collection.songs; artwork = collection.coverURL ?? envelope.coverURL
        default: throw DownloadFailure.songUnavailable
        }
        try check(captured)
        guard !songs.isEmpty else { throw DownloadFailure.songUnavailable }
        var seen = Set<String>()
        return try songs.enumerated().compactMap { position, song in
            guard seen.insert(song.mid).inserted else { return nil }
            let number = max(1, song.trackNumber ?? (request.kind == "album" ? position + 1 : 1))
            var metadata = QQMusicDownloadMetadata(track: song.track, trackNumber: number,
                discNumber: max(1, song.discNumber ?? 1), quality: request.quality)
            if request.kind == "playlist" {
                metadata.playlistID = request.id; metadata.playlistTitle = envelope.title
                metadata.playlistPosition = position + 1; metadata.playlistArtworkURL = artwork
            }
            contexts[metadata.transferID] = captured
            return DownloadTransfer(id: UUID(), metadata: try JSONEncoder().encode(metadata),
                                    state: localFile(for: metadata) == nil ? .queued : .completed)
        }
    }

    private func collectionID(_ metadata: QQMusicDownloadMetadata) -> String {
        metadata.playlistID ?? (metadata.track.discID.isEmpty ? metadata.track.remoteSource?.itemID ?? metadata.track.id : metadata.track.discID)
    }
    private func localFile(for metadata: QQMusicDownloadMetadata) -> URL? {
        let record = library.collection(provider: id, kind: metadata.playlistID == nil ? "album" : "playlist", id: collectionID(metadata))
        guard record?.manifest.entries.contains(where: {
            $0.itemID == metadata.track.remoteSource?.itemID && ($0.requestedQuality ?? $0.quality) == metadata.quality.rawValue
        }) == true else { return nil }
        return record?.localFile(for: metadata.track)
    }

    func source(_ transfer: DownloadTransfer) async throws -> DownloadSource? {
        let captured = try context()
        var metadata = try JSONDecoder().decode(QQMusicDownloadMetadata.self, from: transfer.metadata)
        if let original = contexts[metadata.transferID], original != captured {
            // Fail this attempt; an explicit retry can acquire a source under the
            // new account. Never silently continue a queued account-owned plan.
            contexts.removeValue(forKey: metadata.transferID)
            throw QQMusicDownloadError.sessionChanged
        }
        contexts[metadata.transferID] = captured
        if localFile(for: metadata) != nil { return nil }
        guard metadata.track.remoteSource?.providerID == id, let mid = metadata.track.remoteSource?.itemID else { throw DownloadFailure.songUnavailable }
        if let file = library.localFile(for: metadata.track, quality: metadata.quality.rawValue) {
            for record in library.collections where record.manifest.source.provider == id {
                if let entry = record.manifest.entries.first(where: {
                    $0.itemID == mid && ($0.requestedQuality ?? $0.quality) == metadata.quality.rawValue
                }), let quality = entry.quality, record.localFile(for: metadata.track) == file,
                   ["mp3", "flac"].contains(file.pathExtension.lowercased()) {
                    metadata.actualQuality = quality; metadata.type = file.pathExtension.lowercased()
                    return DownloadSource(url: file, metadata: try JSONEncoder().encode(metadata))
                }
            }
        }
        let key = AudioPlaybackCache.Key(trackID: metadata.track.id, scope: captured.scope, quality: metadata.quality.rawValue)
        if let entry = AudioPlaybackCache.shared.entry(for: key) {
            let file = AudioPlaybackCache.shared.directory.appendingPathComponent(entry.filename)
            if ["mp3", "flac"].contains(file.pathExtension.lowercased()) {
                metadata.actualQuality = entry.actualQuality; metadata.type = file.pathExtension.lowercased()
                return DownloadSource(url: file, metadata: try JSONEncoder().encode(metadata))
            }
        }
        let source = try await api.stream(mid: mid, quality: metadata.quality)
        try check(captured)
        guard !source.isPreview else { throw DownloadFailure.songUnavailable }
        metadata.actualQuality = source.actualQuality; metadata.type = source.fileExtension
        return DownloadSource(url: source.url, metadata: try JSONEncoder().encode(metadata))
    }

    func finalize(_ file: URL, metadata data: Data, staging: URL) async throws -> PreparedDownload {
        let metadata = try JSONDecoder().decode(QQMusicDownloadMetadata.self, from: data)
        // Restored completed transfers may finish without acquiring a new URL. During
        // this process lifetime, a transfer always retains its originating account.
        let captured = try contexts[metadata.transferID] ?? context()
        try check(captured)
        guard let type = metadata.type, let quality = metadata.actualQuality,
              let mid = metadata.track.remoteSource?.itemID else { throw DownloadFailure.songUnavailable }
        let audio = try await Self.prepare(file, type: type, staging: staging)
        defer { try? FileManager.default.removeItem(at: audio) }
        try check(captured)
        let title = OfflinePaths.directoryName(metadata.track.title, fallback: mid)
        let safeMid = OfflinePaths.directoryName(mid, fallback: "song")
        let filename = String(format: "%02d", metadata.playlistPosition ?? metadata.trackNumber) + " " + title + " [\(safeMid)]." + type
        let destination = try OfflinePaths.file(filename, inside: staging)
        try FileManager.default.moveItem(at: audio, to: destination)
        let access = OfflineFolderAccess(url: staging)
        let snapshot = try await AudioTagEditor.shared.read(destination, access: access)
        try check(captured)
        var tags = snapshot.document
        tags.setText("TITLE", metadata.track.title)
        tags.setText("ARTIST", metadata.track.artists)
        tags.setText("ALBUM", metadata.track.albumTitle)
        tags.setText("ALBUMARTIST", metadata.track.artists)
        tags.setText("TRACKNUMBER", String(metadata.trackNumber))
        tags.setText("DISCNUMBER", String(metadata.discNumber))
        if let url = metadata.track.coverURL {
            do {
                let (data, response) = try await artworkSession.data(for: URLRequest(url: url, timeoutInterval: 20))
                if let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode), data.count <= 20_000_000 {
                    tags.cover = data.base64EncodedString()
                }
            } catch is CancellationError { throw CancellationError() }
            catch { /* Artwork is optional; retain successfully downloaded audio. */ }
            try check(captured)
        }
        do {
            let lyrics = try await api.lyrics(mid: mid)
            let text = Self.lyricsText(lyrics)
            if !text.isEmpty { tags.setText("LYRICS", text) }
        } catch is CancellationError { throw CancellationError() }
        catch { /* Missing lyrics must not discard full audio. */ }
        try check(captured)
        try await AudioTagEditor.shared.save(tags, snapshot: snapshot, url: destination, access: access)
        try check(captured)
        let track = Track(discID: metadata.track.discID, number: String(metadata.trackNumber), title: metadata.track.title,
            artists: metadata.track.artists, albumTitle: metadata.track.albumTitle, coverURL: metadata.track.coverURL,
            duration: metadata.track.duration, remoteSource: metadata.track.remoteSource)
        let kind = metadata.playlistID == nil ? "album" : "playlist", collectionID = collectionID(metadata)
        let collectionTitle = metadata.playlistTitle ?? (track.albumTitle.isEmpty ? track.title : track.albumTitle)
        let manifest = LibraryManifest(source: LibrarySource(provider: id, kind: kind, id: collectionID), title: collectionTitle,
            artist: track.artists, artworkURL: metadata.playlistID == nil ? track.coverURL : metadata.playlistArtworkURL,
            entries: [.init(relativePath: filename, itemID: mid, track: track, quality: quality, requestedQuality: metadata.quality.rawValue)])
        let folderName: String
        if let existing = library.collection(provider: id, kind: kind, id: collectionID), let root = library.downloadRoot,
           let relative = try? OfflinePaths.relativePath(of: existing.directoryURL, inside: root) { folderName = relative }
        else { folderName = "qqmusic/" + (kind == "playlist" ? "歌单/" : "专辑/") + OfflinePaths.directoryName(collectionTitle, fallback: collectionID) + " [" + OfflinePaths.directoryName(collectionID, fallback: "collection") + "]" }
        return PreparedDownload(folderName: folderName, provenance: .updatingCollection(manifest))
    }

    func completed(_ request: Data, transfers: [DownloadTransfer]) async throws {
        for transfer in transfers {
            guard let metadata = try? JSONDecoder().decode(QQMusicDownloadMetadata.self, from: transfer.metadata),
                  let captured = contexts.removeValue(forKey: metadata.transferID) else { continue }
            if transfer.state == .completed {
                AudioPlaybackCache.shared.remove(.init(trackID: metadata.track.id, scope: captured.scope, quality: metadata.quality.rawValue))
            }
        }
    }

    nonisolated static func lyricsText(_ lyrics: LocalLyrics) -> String {
        guard lyrics.isTimed else { return lyrics.plainText }
        return lyrics.lines.flatMap { line in
            let centiseconds = Int((line.time * 100).rounded())
            let timestamp = String(format: "[%02d:%02d.%02d]", centiseconds / 6000, centiseconds / 100 % 60, centiseconds % 100)
            return line.text.components(separatedBy: .newlines).map { timestamp + $0 }
        }.joined(separator: "\n")
    }

    @concurrent private static func prepare(_ file: URL, type: String, staging: URL) async throws -> URL {
        try Task.checkCancellation()
        let handle = try FileHandle(forReadingFrom: file)
        defer { try? handle.close() }
        let bytes = try handle.read(upToCount: 8) ?? Data()
        let isFLAC = bytes.starts(with: Data("fLaC".utf8))
        let isMP3 = bytes.starts(with: Data("ID3".utf8)) || (bytes.count >= 2 && bytes[0] == 0xff && bytes[1] & 0xe0 == 0xe0)
        guard (type == "flac" && isFLAC) || (type == "mp3" && isMP3) else { throw QQMusicDownloadError.invalidAudio }
        let result = staging.appendingPathComponent(UUID().uuidString).appendingPathExtension(type)
        do {
            try FileManager.default.copyItem(at: file, to: result)
            try Task.checkCancellation()
            return result
        } catch { try? FileManager.default.removeItem(at: result); throw error }
    }
}

extension DownloadStore {
    func enqueueQQMusic(kind: String, id: String, title: String, coverURL: URL?, quality: QQMusicQuality) async {
        guard let payload = try? JSONEncoder().encode(QQMusicDownloadRequest(kind: kind, id: id, quality: quality)) else { return }
        await enqueue(providerID: "qqmusic", request: DownloadRequest(title: title, identity: "\(kind)/\(id)", coverURL: coverURL, payload: payload))
    }
    func enqueueQQMusicSong(_ track: Track, quality: QQMusicQuality) async {
        guard track.remoteSource?.providerID == "qqmusic", let mid = track.remoteSource?.itemID else { return }
        await enqueueQQMusic(kind: "single", id: mid, title: track.title, coverURL: track.coverURL, quality: quality)
    }
}
