import Foundation
import Observation

/// Optional account capabilities. Missing providers never fall back to a different platform.
@Observable @MainActor final class LibraryProviderRegistry {
    struct Provider {
        let title: String
        var onlineSongs: ((LibraryExport.Collection) async throws -> [Track])?
        var exportSettings: () -> [String: String] = { [:] }
        var applySettings: ([String: String]) -> Void = { _ in }
        var exportCredential: () -> String? = { nil }
        var restoreCredential: (String) async -> LibraryRestoreReport.Login = { _ in .expired }
        var artistLookupKey: (String) -> String = { $0 }
        var artistAvatar: (String) -> URL? = { _ in nil }
        var loadArtistAvatar: (String) async -> Void = { _ in }
    }
    private var providers: [String: Provider] = [:]
    @ObservationIgnored private var revisions: [String: Int] = [:]
    @ObservationIgnored private var reads: [String: [UUID: Task<[Track], Error>]] = [:]
    @ObservationIgnored private var restores: [String: Task<LibraryRestoreReport.Login, Never>] = [:]
    func register(_ id: String, provider: Provider) { revisions[id, default: 0] += 1; providers[id] = provider }
    func unregister(_ id: String) {
        revisions[id, default: 0] += 1
        providers[id] = nil
        reads.removeValue(forKey: id)?.values.forEach { $0.cancel() }
        restores.removeValue(forKey: id)?.cancel()
    }
    func onlineSongs(_ item: LibraryExport.Collection) async throws -> [Track] {
        guard let load = providers[item.providerID]?.onlineSongs else { throw ProviderError.unavailable }
        let revision = revisions[item.providerID, default: 0]
        let id = UUID()
        let task = Task { try await load(item) }
        reads[item.providerID, default: [:]][id] = task
        defer { reads[item.providerID]?[id] = nil }
        let songs = try await withTaskCancellationHandler {
            try await task.value
        } onCancel: { task.cancel() }
        try Task.checkCancellation()
        guard revisions[item.providerID, default: 0] == revision else { throw CancellationError() }
        return songs
    }
    func settings() -> [String: [String: String]] { providers.mapValues { $0.exportSettings() } }
    func apply(_ settings: [String: [String: String]]) {
        for (id, values) in settings { providers[id]?.applySettings(values) }
    }
    func credentials() -> [String: String] { providers.compactMapValues { $0.exportCredential() } }
    func restore(_ credentials: [String: String]) async -> [String: LibraryRestoreReport.Account] {
        var results: [String: LibraryRestoreReport.Account] = [:]
        for id in credentials.keys.sorted() {
            guard let provider = providers[id], let credential = credentials[id] else { continue }
            let revision = revisions[id, default: 0]
            let task = Task { await provider.restoreCredential(credential) }
            restores[id] = task
            let status = await withTaskCancellationHandler {
                await task.value
            } onCancel: { task.cancel() }
            guard revisions[id, default: 0] == revision, !Task.isCancelled else { continue }
            restores[id] = nil
            results[id] = .init(title: provider.title, status: status)
        }
        return results
    }
    func artistLookupKey(named name: String) -> String {
        providers.keys.sorted().map { id in id + ":" + (providers[id]?.artistLookupKey(name) ?? name) }.joined(separator: "|")
    }
    func artistAvatar(named name: String) -> URL? {
        providers.keys.sorted().compactMap { providers[$0]?.artistAvatar(name) }.first
    }
    func loadArtistAvatar(named name: String) async {
        for id in providers.keys.sorted() { await providers[id]?.loadArtistAvatar(name) }
    }
    enum ProviderError: Error { case unavailable, incomplete }
}
