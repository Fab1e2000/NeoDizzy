import Foundation

/// 旧调用方的兼容入口，所有磁盘提交集中到通用本地库。
extension OfflineLibraryWorker {
    func importAlbum(from extractedURL: URL, detail: DiscDetail, into folder: OfflineFolderAccess) throws -> LibraryCollection {
        try coordinatedWrite(folder.url) { root in try Self.importDirectory(from: extractedURL, detail: detail, into: root) }
    }
    func importGift(from source: URL, detail: DiscDetail, albumDirectory: URL?, into folder: OfflineFolderAccess) throws {
        try coordinatedWrite(folder.url) { root in
            try Self.importGiftDirectory(from: source, detail: detail, albumDirectory: albumDirectory, into: root)
        }
    }
    @discardableResult
    nonisolated static func importDirectory(from source: URL, detail: DiscDetail, into root: URL) throws -> LibraryCollection {
        let prepared = try DizzyLabDownloadProvider.prepared(.init(album: DownloadAlbum(detail), format: ""), staging: source)
        guard let result = try commitDirectory(staging: source, folderName: prepared.folderName, provenance: prepared.provenance, into: root) else {
            throw OfflineLibraryError.invalidManifest
        }
        return result
    }
    nonisolated static func importGiftDirectory(from source: URL, detail: DiscDetail, albumDirectory: URL? = nil, into root: URL) throws {
        let relative = try albumDirectory.map {
            $0.standardizedFileURL.resolvingSymlinksInPath() == root.standardizedFileURL.resolvingSymlinksInPath()
                ? "" : try OfflinePaths.relativePath(of: $0, inside: root)
        }
        let prepared = try DizzyLabDownloadProvider.prepared(.init(album: DownloadAlbum(detail), format: "gift"), staging: source, folderName: relative)
        _ = try commitDirectory(staging: source, folderName: prepared.folderName, provenance: prepared.provenance, into: root)
    }
}
