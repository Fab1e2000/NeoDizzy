import Foundation

nonisolated struct DizzyLabDownloadRequest: Codable, Sendable {
    let album: DownloadAlbum
    let format: String
    var isGift: Bool { format == "gift" }
    /// DizzyLab 的下载统一放在 dizzylab/ 下，再按社团分。
    var folderName: String {
        let label = OfflinePaths.directoryName(album.labelName ?? "", fallback: "未知社团")
        let title = OfflinePaths.directoryName(album.title, fallback: "未命名专辑")
        return "dizzylab/\(label)/\(title) [\(OfflinePaths.identifierName(album.id))]"
    }
    var request: DownloadRequest {
        DownloadRequest(title: isGift ? "\(album.title) · 特典" : album.title,
                        identity: "\(album.id)/\(isGift ? "gift" : "album")", coverURL: album.coverURL,
                        payload: (try? JSONEncoder().encode(self)) ?? Data())
    }
}

final class DizzyLabDownloadProvider: DownloadProvider {
    let id = "dizzylab"
    func summary(for transfer: DownloadTransfer) -> DownloadTransferSummary? {
        DownloadTransferSummary(title: "专辑压缩包")
    }
    private let library: OfflineLibraryStore
    init(library: OfflineLibraryStore) { self.library = library }
    func title(_ data: Data) -> String { (try? JSONDecoder().decode(DownloadRequest.self, from: data).title) ?? "下载专辑" }
    func identity(_ data: Data) -> String { (try? JSONDecoder().decode(DownloadRequest.self, from: data).identity) ?? "" }
    func plan(_ data: Data) async throws -> [DownloadTransfer] {
        let request = try JSONDecoder().decode(DownloadRequest.self, from: data)
        _ = try JSONDecoder().decode(DizzyLabDownloadRequest.self, from: request.payload)
        return [DownloadTransfer(id: UUID(), metadata: request.payload)]
    }
    func source(_ transfer: DownloadTransfer) async throws -> DownloadSource? {
        let request = try JSONDecoder().decode(DizzyLabDownloadRequest.self, from: transfer.metadata)
        let options = try await DizzyPages.shared.downloadOptions(discID: request.album.id, gift: request.isGift)
        guard let fresh = options.first(where: { $0.format == request.format }) else { throw DownloadFailure.unavailable }
        let url = try await DownloadLinkResolver.resolve(fresh.url, credentials: DizzyHTTPClient.shared.credentials)
        return DownloadSource(url: url, metadata: transfer.metadata,
                              headers: ["User-Agent": DizzyHTTPClient.userAgent, "Referer": DizzyURL.site.absoluteString + "/"])
    }
    func finalize(_ file: URL, metadata: Data, staging: URL) async throws -> PreparedDownload {
        let request = try JSONDecoder().decode(DizzyLabDownloadRequest.self, from: metadata)
        // 解压器拥有目标目录的创建与清理。
        try FileManager.default.removeItem(at: staging)
        try await SafeZipExtractor.extract(file, into: staging, expectedTracks: request.isGift ? [] : request.album.tracks)
        var folderName = request.folderName
        if request.isGift, let record = library.collection(provider: id, kind: "album", id: request.album.id),
           let root = library.downloadRoot,
           let relative = try? OfflinePaths.relativePath(of: record.directoryURL, inside: root) { folderName = relative }
        return try Self.prepared(request, staging: staging, folderName: folderName)
    }
    nonisolated static func prepared(_ request: DizzyLabDownloadRequest, staging: URL, folderName: String? = nil) throws -> PreparedDownload {
        let source = LibrarySource(provider: "dizzylab", kind: "album", id: request.album.id)
        if request.isGift {
            return PreparedDownload(folderName: folderName ?? request.folderName,
                provenance: .attachment(source, subdirectory: "特典", marker: ".neodizzy-gift.json"))
        }
        let paths = try OfflineLibraryWorker.extractedFiles(in: staging)
        let files = try AudioFileMatcher.match(tracks: request.album.tracks, relativePaths: paths)
        let manifest = try LibraryManifest(detail: request.album.detail, files: files, coverPath: OfflineLibraryWorker.preferredCover(in: paths))
        return PreparedDownload(folderName: folderName ?? request.folderName,
            provenance: .collection(manifest, merge: false, preserving: ["特典"], placeholderMarker: ".neodizzy-gift.json"))
    }

    nonisolated static func migrate(_ data: Data) -> [DownloadJob]? {
        struct LegacyJob: Decodable {
            let id: UUID
            let album: DownloadAlbum
            let format: String
            let state: DownloadJob.State
            let progress: Double?
            let failureMessage: String?
        }
        guard let old = try? JSONDecoder().decode([LegacyJob].self, from: data) else { return nil }
        return old.map { legacy in
            let request = DizzyLabDownloadRequest(album: legacy.album, format: legacy.format)
            var job = DownloadJob(id: legacy.id, album: legacy.album, format: legacy.format)
            job.state = legacy.state; job.progress = legacy.progress; job.failureMessage = legacy.failureMessage
            if legacy.state.isActive && legacy.state != .queued {
                job.transfers = [DownloadTransfer(id: legacy.id, metadata: (try? JSONEncoder().encode(request)) ?? Data(), state: .downloading)]
            }
            return job
        }
    }
}

extension DownloadJob {
    init(id: UUID, album: DownloadAlbum, format: String) {
        let request = DizzyLabDownloadRequest(album: album, format: format).request
        self.init(id: id, providerID: "dizzylab", requestData: (try? JSONEncoder().encode(request)) ?? Data())
    }
}

extension DownloadStore {
    func enqueue(detail: DiscDetail, option: DownloadOption) async {
        await enqueue(providerID: "dizzylab", request: DizzyLabDownloadRequest(album: DownloadAlbum(detail), format: option.format).request)
    }
}

extension DownloadJob {
    private var dizzyRequest: DizzyLabDownloadRequest? {
        guard providerID == "dizzylab", let payload = request?.payload else { return nil }
        return try? JSONDecoder().decode(DizzyLabDownloadRequest.self, from: payload)
    }
    var discID: String { dizzyRequest?.album.id ?? "" }
    var isGift: Bool { dizzyRequest?.isGift ?? false }
}
