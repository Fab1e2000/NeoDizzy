import Foundation

nonisolated struct DownloadTransfer: Codable, Sendable, Identifiable {
    enum State: String, Codable, Sendable { case queued, downloading, downloaded, completed, failed }
    let id: UUID
    var metadata: Data
    var state: State = .queued
    var failure: String?
}

nonisolated struct DownloadSource: Sendable {
    let url: URL
    let metadata: Data
    var headers: [String: String] = [:]
}

nonisolated struct PreparedDownload: Sendable {
    let folderName: String
    let provenance: LibraryProvenance
}

/// 请求和传输元数据只能包含稳定标识；地址与授权仅存在于 DownloadSource 内存中。
@MainActor protocol DownloadProvider {
    var id: String { get }
    func title(_ request: Data) -> String
    func identity(_ request: Data) -> String
    func plan(_ request: Data) async throws -> [DownloadTransfer]
    func source(_ transfer: DownloadTransfer) async throws -> DownloadSource?
    func finalize(_ file: URL, metadata: Data, staging: URL) async throws -> PreparedDownload
    func completed(_ request: Data, transfers: [DownloadTransfer]) async throws
}

extension DownloadProvider {
    func completed(_ request: Data, transfers: [DownloadTransfer]) async throws {}
}
