import Foundation

// 兼容现有调用方；来源记录和文件查找均由通用模型实现。
typealias OfflineManifest = LibraryManifest
typealias OfflineAlbum = LibraryCollection

extension LibraryManifest {
    init(detail: DiscDetail, files: [String: String], coverPath: String?) throws {
        guard !detail.id.isEmpty, !detail.tracks.isEmpty,
              Set(detail.tracks.map(\.number)).count == detail.tracks.count,
              detail.tracks.allSatisfy({ $0.discID == detail.id && !$0.number.isEmpty && $0.localSource == nil && $0.remoteSource == nil }) else {
            throw OfflineLibraryError.invalidManifest
        }
        let entries = try detail.tracks.map { track in
            guard let path = files[track.number] else { throw OfflineLibraryError.missingTrack(track.title) }
            return Entry(relativePath: path, itemID: "\(detail.id)/\(track.number)", track: track)
        }
        self.init(source: LibrarySource(provider: "dizzylab", kind: "album", id: detail.id),
                  title: detail.summary.title, artist: detail.summary.labelName ?? "未知社团",
                  artworkURL: detail.summary.coverURL, coverPath: coverPath, entries: entries,
                  extra: .object(["releaseDate": detail.releaseDate.map(LibraryJSON.string) ?? .null,
                                  "description": .string(detail.description), "credits": .string(detail.credits),
                                  "labelDescription": .string(detail.labelDescription),
                                  "labelName": .string(detail.summary.labelName ?? "未知社团")]))
    }

    var discID: String { source.id }
    private func dizzyText(_ key: String) -> String? {
        guard case .object(let fields) = extra, case .string(let value) = fields[key] else { return nil }
        return value
    }
    var labelName: String { dizzyText("labelName") ?? artist }
    var releaseDate: String? { dizzyText("releaseDate") }
    var description: String { dizzyText("description") ?? "" }
    var credits: String { dizzyText("credits") ?? "" }
    var labelDescription: String { dizzyText("labelDescription") ?? "" }
}

extension LibraryCollection {
    var discID: String { manifest.source.id }
    var labelName: String { manifest.labelName }
    var detail: DiscDetail {
        let summary = DiscSummary(id: discID, title: title, coverURL: coverURL, labelName: labelName, isOwned: true)
        return DiscDetail(summary: summary, releaseDate: manifest.releaseDate,
                          description: manifest.description, credits: manifest.credits,
                          labelDescription: manifest.labelDescription, hasGift: false,
                          tracks: tracks, streams: [:])
    }
}


extension OfflineLibraryStore {
    var albums: [LibraryCollection] { collections }

    func album(id: String) -> LibraryCollection? {
        collection(provider: "dizzylab", kind: "album", id: id)
    }

    func availableTrackIDs(discID: String) async throws -> Set<String> {
        Set(try await localTrackKeys(provider: "dizzylab", collectionID: discID).map(\.itemID))
    }

    func importAlbum(from extractedURL: URL, detail: DiscDetail) async throws {
        try await performImport { worker, folder in
            try await worker.importAlbum(from: extractedURL, detail: detail, into: folder)
        }
    }

    func importGift(from extractedURL: URL, detail: DiscDetail) async throws {
        let directory = collection(provider: "dizzylab", kind: "album", id: detail.id)?.directoryURL
        try await performImport { worker, folder in
            let inside = directory.flatMap { url -> URL? in
                let equal = LocalLibraryScanner.canonical(url) == LocalLibraryScanner.canonical(folder.url)
                return equal || (try? OfflinePaths.relativePath(of: url, inside: folder.url)) != nil ? url : nil
            }
            try await worker.importGift(from: extractedURL, detail: detail, albumDirectory: inside, into: folder)
            return nil
        }
    }
}
