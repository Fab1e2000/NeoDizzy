import Foundation

/// 旧格式只在内存里转换，扫描不会把转换结果写回磁盘。
nonisolated struct LegacyLibraryManifest: Decodable {
    struct Entry: Decodable {
        let track: Track
        let relativePath: String
    }
    let discID: String
    let title: String
    let labelName: String
    let releaseDate: String?
    let description: String
    let credits: String
    let labelDescription: String
    let artworkURL: URL?
    let coverPath: String?
    let entries: [Entry]

    func converted() throws -> LibraryManifest {
        guard entries.allSatisfy({ $0.track.discID == discID && $0.track.remoteSource == nil }) else {
            throw OfflineLibraryError.invalidManifest
        }
        return LibraryManifest(source: LibrarySource(provider: "dizzylab", kind: "album", id: discID),
            title: title, artist: labelName, artworkURL: artworkURL, coverPath: coverPath,
            entries: entries.map { .init(relativePath: $0.relativePath, itemID: "\(discID)/\($0.track.number)", track: $0.track) },
            extra: .object(["releaseDate": releaseDate.map(LibraryJSON.string) ?? .null,
                            "description": .string(description), "credits": .string(credits),
                            "labelDescription": .string(labelDescription), "labelName": .string(labelName)]))
    }
}
