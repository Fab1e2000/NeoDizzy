import Foundation

nonisolated struct NeteaseDownloadRequest: Codable {
    let kind: String
    let id: Int
    let quality: NeteaseQuality
}

nonisolated struct NeteaseDownloadMetadata: Codable {
    let track: Track
    let albumArtist: String
    let trackNumber: Int
    let discNumber: Int
    let quality: NeteaseQuality
    var actualQuality: String?
    var type: String?
    var bitrate: Int?
    var playlistID: String? = nil
    var playlistTitle: String? = nil
    var playlistPosition: Int? = nil
    var playlistArtworkURL: URL? = nil
}

final class NeteaseDownloadProvider: DownloadProvider {
    let id = "netease"
    let api: NeteaseAPI
    let library: OfflineLibraryStore
    let artworkSession: URLSession
    var playlistCompleted: ((String, String, [Track]) async throws -> Void)?
    init(api: NeteaseAPI, library: OfflineLibraryStore, artworkSession: URLSession = .shared) {
        self.api = api; self.library = library; self.artworkSession = artworkSession
    }
    func title(_ data: Data) -> String { (try? JSONDecoder().decode(DownloadRequest.self, from: data).title) ?? "下载歌曲" }
    func identity(_ data: Data) -> String { (try? JSONDecoder().decode(DownloadRequest.self, from: data).identity) ?? "" }
    func plan(_ data: Data) async throws -> [DownloadTransfer] {
        let envelope = try JSONDecoder().decode(DownloadRequest.self, from: data)
        let request = try JSONDecoder().decode(NeteaseDownloadRequest.self, from: envelope.payload)
        var playlistArtworkURL = envelope.coverURL
        var songs: [NeteaseSong]
        var albums: [Int: (NeteaseAlbum, [NeteaseSong])] = [:]
        switch request.kind {
        case "single": songs = try await api.songs([request.id])
        case "album":
            let result = try await api.album(request.id)
            songs = result.1; albums[request.id] = result
        case "playlist":
            let playlist = try await api.playlist(request.id)
            playlistArtworkURL = playlist.artworkURL ?? envelope.coverURL
            let ids = playlist.trackIds?.map(\.id) ?? playlist.tracks?.map(\.id) ?? []
            songs = []
            for start in stride(from: 0, to: ids.count, by: 100) {
                try Task.checkCancellation()
                let batch = Array(ids[start..<min(start + 100, ids.count)])
                let received = try await api.songs(batch)
                let byID = Dictionary(received.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
                songs += batch.map { byID[$0] ?? NeteaseSong(id: $0, name: "不可用歌曲", artists: [], album: nil) }
            }
        default: throw DownloadFailure.songUnavailable
        }
        guard !songs.isEmpty else { throw DownloadFailure.songUnavailable }
        // 歌曲详情通常已带曲序；只为缺曲序的歌曲补查专辑，避免大歌单逐张串行查询。
        var missingAlbums: [Int] = []
        for song in songs where song.trackNumber == nil {
            if let id = song.album?.id, id > 0, albums[id] == nil, !missingAlbums.contains(id) { missingAlbums.append(id) }
        }
        albums.merge(try await fetchAlbums(missingAlbums)) { current, _ in current }
        var result: [DownloadTransfer] = []
        var seen = Set<Int>()
        for (position, song) in songs.enumerated() where seen.insert(song.id).inserted {
            try Task.checkCancellation()
            let album = song.album.flatMap { albums[$0.id] }
            let number = max(1, song.trackNumber ?? album?.1.firstIndex(where: { $0.id == song.id }).map { $0 + 1 } ?? 1)
            var metadata = NeteaseDownloadMetadata(track: song.track,
                albumArtist: album?.0.artist?.name ?? song.album?.artist?.name ?? song.track.artists, trackNumber: number,
                discNumber: max(1, Int(song.discNumber ?? "1") ?? 1), quality: request.quality)
            if request.kind == "playlist" {
                metadata.playlistID = String(request.id)
                metadata.playlistTitle = envelope.title
                metadata.playlistPosition = position + 1
                metadata.playlistArtworkURL = playlistArtworkURL
            }
            let state: DownloadTransfer.State = localFile(for: metadata) == nil ? .queued : .completed
            result.append(DownloadTransfer(id: UUID(), metadata: try JSONEncoder().encode(metadata), state: state))
        }
        return result
    }
    /// 并发补查专辑，单张失败只影响该专辑的曲序补全。
    private func fetchAlbums(_ ids: [Int]) async throws -> [Int: (NeteaseAlbum, [NeteaseSong])] {
        let api = api
        var albums: [Int: (NeteaseAlbum, [NeteaseSong])] = [:]
        try await withThrowingTaskGroup(of: (Int, (NeteaseAlbum, [NeteaseSong])?).self) { group in
            var pending = ids.makeIterator()
            func fetch(_ id: Int) {
                group.addTask {
                    do { return (id, try await api.album(id)) }
                    catch is CancellationError { throw CancellationError() }
                    catch { return (id, nil) }
                }
            }
            for _ in 0..<Self.albumLookupConcurrency { if let id = pending.next() { fetch(id) } }
            while let (id, album) = try await group.next() {
                if let album { albums[id] = album }
                if let id = pending.next() { fetch(id) }
            }
        }
        try Task.checkCancellation()
        return albums
    }
    static let albumLookupConcurrency = 4
    private func localFile(for metadata: NeteaseDownloadMetadata) -> URL? {
        let record = library.collection(provider: id, kind: metadata.playlistID == nil ? "album" : "playlist", id: metadata.playlistID ?? metadata.track.discID)
        guard record?.manifest.entries.contains(where: { $0.itemID == metadata.track.remoteSource?.itemID && ($0.requestedQuality ?? $0.quality) == metadata.quality.rawValue }) == true else { return nil }
        return record?.localFile(for: metadata.track)
    }

    func source(_ transfer: DownloadTransfer) async throws -> DownloadSource? {
        var metadata = try JSONDecoder().decode(NeteaseDownloadMetadata.self, from: transfer.metadata)
        if localFile(for: metadata) != nil { return nil }
        guard let songID = (metadata.track.remoteSource?.itemID).flatMap(Int.init),
              let albumID = Int(metadata.track.discID), albumID > 0 else { throw DownloadFailure.songUnavailable }
        if let file = library.localFile(for: metadata.track, quality: metadata.quality.rawValue) {
            for record in library.collections {
                if let entry = record.manifest.entries.first(where: { $0.itemID == metadata.track.remoteSource?.itemID && ($0.requestedQuality ?? $0.quality) == metadata.quality.rawValue }),
                   let actual = entry.quality, record.localFile(for: metadata.track) == file {
                    metadata.actualQuality = actual; metadata.type = file.pathExtension; metadata.bitrate = 0
                    return DownloadSource(url: file, metadata: try JSONEncoder().encode(metadata))
                }
            }
        }
        let key = api.cacheKey(for: metadata.track.id, quality: metadata.quality)
        if let entry = AudioPlaybackCache.shared.entry(for: key) {
            let file = AudioPlaybackCache.shared.directory.appendingPathComponent(entry.filename)
            if AudioFileMatcher.extensions.contains(file.pathExtension) {
                metadata.actualQuality = entry.actualQuality; metadata.type = file.pathExtension; metadata.bitrate = 0
                return DownloadSource(url: file, metadata: try JSONEncoder().encode(metadata))
            }
        }
        let source = try await api.downloadSource(songID, quality: metadata.quality)
        metadata.actualQuality = source.level; metadata.type = source.type; metadata.bitrate = source.bitrate
        return DownloadSource(url: source.url, metadata: try JSONEncoder().encode(metadata))
    }
    func finalize(_ file: URL, metadata data: Data, staging: URL) async throws -> PreparedDownload {
        let metadata = try JSONDecoder().decode(NeteaseDownloadMetadata.self, from: data)
        guard let declaredType = metadata.type, let level = metadata.actualQuality,
              let songID = (metadata.track.remoteSource?.itemID).flatMap(Int.init) else { throw DownloadFailure.songUnavailable }
        let audio = try await NeteaseDownloadedAudio.prepare(file, declaredType: declaredType.lowercased(), staging: staging)
        defer { try? FileManager.default.removeItem(at: audio) }
        try Task.checkCancellation()
        let type = audio.pathExtension
        let title = OfflinePaths.directoryName(metadata.track.title, fallback: String(songID))
        // Different discs (or sanitized titles) can share a track number and name.
        // Keep every remote song distinct when merging files into one collection.
        let filename = String(format: "%02d", metadata.playlistPosition ?? metadata.trackNumber) + " " + title + " [\(songID)]." + type
        let path = filename
        let destination = try OfflinePaths.file(path, inside: staging)
        try FileManager.default.moveItem(at: audio, to: destination)
        let access = OfflineFolderAccess(url: staging)
        let snapshot = try await AudioTagEditor.shared.read(destination, access: access)
        var tags = snapshot.document
        tags.setText("TITLE", metadata.track.title)
        tags.setText("ARTIST", metadata.track.artists)
        tags.setText("ALBUM", metadata.track.albumTitle)
        tags.setText("ALBUMARTIST", metadata.albumArtist)
        tags.setText("TRACKNUMBER", String(metadata.trackNumber))
        tags.setText("DISCNUMBER", String(metadata.discNumber))
        if let url = metadata.track.coverURL {
            do { tags.cover = try await artwork(url).base64EncodedString() }
            catch is CancellationError { throw CancellationError() }
            catch { try Task.checkCancellation() /* 封面是附加信息，取不到也保留已下载的音频。 */ }
        }
        do {
            if let lyrics = try await api.downloadLyrics(songID), !lyrics.isEmpty { tags.setText("LYRICS", lyrics) }
        } catch is CancellationError { throw CancellationError() }
        catch { /* 没有歌词不影响完整音频下载。 */ }
        try await AudioTagEditor.shared.save(tags, snapshot: snapshot, url: destination, access: access)
        let track = Track(discID: metadata.track.discID, number: String(metadata.trackNumber), title: metadata.track.title,
                          artists: metadata.track.artists, albumTitle: metadata.track.albumTitle, coverURL: metadata.track.coverURL,
                          duration: metadata.track.duration, remoteSource: metadata.track.remoteSource)
        let kind = metadata.playlistID == nil ? "album" : "playlist"
        let collectionID = metadata.playlistID ?? track.discID
        let collectionTitle = metadata.playlistTitle ?? track.albumTitle
        let manifest = LibraryManifest(source: LibrarySource(provider: id, kind: kind, id: collectionID),
            title: collectionTitle, artist: metadata.albumArtist, artworkURL: metadata.playlistID == nil ? track.coverURL : metadata.playlistArtworkURL,
            entries: [.init(relativePath: path, itemID: String(songID), track: track, quality: level, requestedQuality: metadata.quality.rawValue)])
        // 网易云的下载统一放在 netease/ 下，再按专辑、歌单分开。
        let name = (metadata.playlistID == nil ? "netease/专辑/" : "netease/歌单/") + OfflinePaths.directoryName(collectionTitle, fallback: collectionID)
        let folderName: String
        if let existing = library.collection(provider: id, kind: kind, id: collectionID), let root = library.downloadRoot,
           let relative = try? OfflinePaths.relativePath(of: existing.directoryURL, inside: root) { folderName = relative }
        else { folderName = name }
        return PreparedDownload(folderName: folderName, provenance: .collection(manifest, merge: true, preserving: [], placeholderMarker: nil))
    }
    private func artwork(_ url: URL) async throws -> Data {
        let (artwork, response) = try await artworkSession.data(for: URLRequest(url: url, timeoutInterval: 20))
        guard (response as? HTTPURLResponse).map({ (200..<300).contains($0.statusCode) }) == true,
              artwork.count <= 20_000_000 else { throw DownloadFailure.invalidResponse }
        return artwork
    }
    func completed(_ data: Data, transfers: [DownloadTransfer]) async throws {
        let envelope = try JSONDecoder().decode(DownloadRequest.self, from: data)
        let request = try JSONDecoder().decode(NeteaseDownloadRequest.self, from: envelope.payload)
        for transfer in transfers where transfer.state == .completed {
            if let metadata = try? JSONDecoder().decode(NeteaseDownloadMetadata.self, from: transfer.metadata) {
                AudioPlaybackCache.shared.remove(api.cacheKey(for: metadata.track.id, quality: metadata.quality))
            }
        }
        if request.kind == "playlist", let playlistCompleted,
           !transfers.contains(where: { (try? JSONDecoder().decode(NeteaseDownloadMetadata.self, from: $0.metadata).playlistID) != nil }) {
            let tracks = try transfers.filter { $0.state == .completed }.map { try JSONDecoder().decode(NeteaseDownloadMetadata.self, from: $0.metadata).track }
            try await playlistCompleted(envelope.title, String(request.id), tracks)
        }
    }
}

extension DownloadStore {
    func enqueueNetease(kind: String, id: Int, title: String, coverURL: URL?, quality: NeteaseQuality) async {
        guard let payload = try? JSONEncoder().encode(NeteaseDownloadRequest(kind: kind, id: id, quality: quality)) else { return }
        await enqueue(providerID: "netease", request: DownloadRequest(title: title, identity: "\(kind)/\(id)", coverURL: coverURL, payload: payload))
    }
    /// 下载一首网易云歌曲；已缓存时直接用缓存文件，不再联网。
    func enqueueNeteaseSong(_ track: Track, quality: NeteaseQuality) async {
        guard track.remoteSource?.providerID == "netease", let id = (track.remoteSource?.itemID).flatMap(Int.init) else { return }
        await enqueueNetease(kind: "single", id: id, title: track.title, coverURL: track.coverURL, quality: quality)
    }
}
