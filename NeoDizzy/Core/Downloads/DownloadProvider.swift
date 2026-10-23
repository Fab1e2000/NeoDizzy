import Foundation

/// Opt-in for platform errors whose descriptions never expose credentials or signed URLs.
nonisolated protocol DownloadDisplayableError: LocalizedError {}

nonisolated struct DownloadTransferSummary: Codable, Sendable {
    let title: String
    var subtitle: String? = nil
}

nonisolated struct DownloadTransfer: Codable, Sendable, Identifiable {
    enum State: String, Codable, Sendable { case queued, downloading, downloaded, processing, completed, failed }
    let id: UUID
    var metadata: Data
    var state: State = .queued
    var failure: String?
    var summary: DownloadTransferSummary? = nil
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
    func summary(for transfer: DownloadTransfer) -> DownloadTransferSummary?
    /// Platform-owned compatibility work; the scheduler never decodes platform payloads.
    func migrateRestoredJob(_ job: DownloadJob) -> DownloadJob
    func restore(jobs: [DownloadJob]) async
    func title(_ request: Data) -> String
    func identity(_ request: Data) -> String
    func plan(_ request: Data) async throws -> [DownloadTransfer]
    func source(_ transfer: DownloadTransfer) async throws -> DownloadSource?
    func finalize(_ file: URL, metadata: Data, staging: URL) async throws -> PreparedDownload
    func completed(_ request: Data, transfers: [DownloadTransfer]) async throws
}

extension DownloadProvider {
    func summary(for transfer: DownloadTransfer) -> DownloadTransferSummary? { nil }
    func migrateRestoredJob(_ job: DownloadJob) -> DownloadJob { job }
    func restore(jobs: [DownloadJob]) async {}
    func completed(_ request: Data, transfers: [DownloadTransfer]) async throws {}
}
