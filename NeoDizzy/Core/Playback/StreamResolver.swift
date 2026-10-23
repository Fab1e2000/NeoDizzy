import Foundation

nonisolated struct RemotePlaybackSource {
    let url: URL
    let expiresAt: Date
    let isPreview: Bool
    var actualQuality: String? = nil
    var fileExtension: String? = nil
}

/// A source owns URL semantics and optional collection preloading. The resolver owns
/// local precedence, expiration and source-scoped cancellation for every provider.
struct PlaybackProvider {
    let stream: (Track) async throws -> RemotePlaybackSource
    var lyrics: ((Track) async throws -> LocalLyrics?)? = nil
    var selectedQuality: (() -> String?)? = nil
    var cacheKey: ((Track) -> AudioPlaybackCache.Key)? = nil
    var prime: (([String: URL], String) -> Void)? = nil
    var invalidate: ((String?) -> Void)? = nil
}

final class StreamResolver {
    private struct Cached {
        let providerID: String
        let collectionID: String
        let source: RemotePlaybackSource
    }
    private var providers: [String: PlaybackProvider] = [:]
    private var cache: [String: Cached] = [:]
    private var revisions: [String: Int] = [:]
    private let now: () -> Date
    private var retainedAccess: OfflineFolderAccess?
    private let localAccess: (Track) -> OfflineFolderAccess?
    private let localFile: (Track) -> URL?
    private let qualityLocalFile: ((Track, String?) -> URL?)?
    private let qualityLocalAccess: ((Track, String?) -> OfflineFolderAccess?)?
    static let refreshMargin: TimeInterval = 120

    init(now: @escaping () -> Date = Date.init,
         localFile: @escaping (Track) -> URL? = { _ in nil },
         localAccess: @escaping (Track) -> OfflineFolderAccess? = { _ in nil },
         qualityLocalFile: ((Track, String?) -> URL?)? = nil,
         qualityLocalAccess: ((Track, String?) -> OfflineFolderAccess?)? = nil) {
        self.now = now
        self.localFile = localFile
        self.localAccess = localAccess
        self.qualityLocalFile = qualityLocalFile
        self.qualityLocalAccess = qualityLocalAccess
    }

    func register(_ id: String, provider: PlaybackProvider) {
        invalidateRemote(id)
        providers[id] = provider
    }
    func register(_ id: String, stream: @escaping (String) async throws -> RemotePlaybackSource,
                  lyrics: @escaping (String) async throws -> LocalLyrics,
                  cacheKey: ((Track) -> AudioPlaybackCache.Key)? = nil, selectedQuality: (() -> String?)? = nil) {
        register(id, provider: PlaybackProvider(stream: { track in
            guard let source = track.remoteSource, source.providerID == id else { throw PlaybackError.unavailable }
            return try await stream(source.itemID)
        }, lyrics: { track in
            guard let source = track.remoteSource, source.providerID == id else { return nil }
            return try await lyrics(source.itemID)
        }, selectedQuality: selectedQuality, cacheKey: cacheKey))
    }
    func unregister(_ id: String) {
        invalidateRemote(id)
        providers[id] = nil
    }
    func audioCacheKey(for track: Track) -> AudioPlaybackCache.Key? {
        guard let id = track.playbackProviderID else { return nil }
        return providers[id]?.cacheKey?(track)
    }
    func actualQuality(for track: Track) -> String? { cache[track.id]?.source.actualQuality }
    func lyrics(for track: Track) async throws -> LocalLyrics? {
        guard let id = track.playbackProviderID, let fetch = providers[id]?.lyrics else { return nil }
        let revision = revisions[id, default: 0]
        let result = try await fetch(track)
        try Task.checkCancellation()
        guard revision == revisions[id, default: 0] else { throw CancellationError() }
        return result
    }
    func isPreview(for track: Track?, url: URL) -> Bool {
        guard !url.isFileURL, let track, let cached = cache[track.id], cached.source.url == url else { return false }
        return cached.source.isPreview
    }
    func selectedQuality(for track: Track) -> String? {
        track.playbackProviderID.flatMap { providers[$0]?.selectedQuality?() }
    }
    func localURL(for track: Track) -> URL? {
        if let qualityLocalFile { return qualityLocalFile(track, selectedQuality(for: track)) }
        return localFile(track)
    }
    private func access(for track: Track) -> OfflineFolderAccess? {
        if let qualityLocalAccess { return qualityLocalAccess(track, selectedQuality(for: track)) }
        return localAccess(track)
    }
    func independentLocalAccess(for track: Track) -> OfflineFolderAccess? { access(for: track) }

    func releaseLocalAccess() { retainedAccess = nil }

    func prime(_ streams: [String: URL], for track: Track) {
        guard let id = track.playbackProviderID else { return }
        prime(streams, providerID: id, collectionID: track.discID)
    }
    func prime(_ streams: [String: URL], providerID: String, collectionID: String) {
        guard !streams.isEmpty else { return }
        invalidate(providerID: providerID, collectionID: collectionID)
        providers[providerID]?.prime?(streams, collectionID)
    }

    func stream(for track: Track, preferLocal: Bool = true, retainAccess: Bool = true) async throws -> URL {
        if (preferLocal || track.localSource != nil), let url = localURL(for: track), url.isFileURL,
           FileManager.default.isReadableFile(atPath: url.path) {
            if retainAccess { retainedAccess = access(for: track) }
            return url
        }
        if preferLocal, let key = audioCacheKey(for: track), let file = AudioPlaybackCache.shared.file(for: key) { return file }
        if track.localSource != nil { throw PlaybackError.localUnavailable }
        if retainAccess { retainedAccess = nil }
        guard let id = track.playbackProviderID, let provider = providers[id] else { throw PlaybackError.unavailable }
        if let cached = cache[track.id], cached.source.expiresAt.timeIntervalSince(now()) > Self.refreshMargin { return cached.source.url }
        let revision = revisions[id, default: 0]
        let result = try await provider.stream(track)
        try Task.checkCancellation()
        guard revision == revisions[id, default: 0] else { throw CancellationError() }
        cache[track.id] = Cached(providerID: id, collectionID: track.discID, source: result)
        return result.url
    }

    func invalidate(for track: Track) {
        guard let id = track.playbackProviderID else { return }
        invalidate(providerID: id, collectionID: track.discID)
    }
    func invalidate(providerID: String, collectionID: String? = nil) {
        revisions[providerID, default: 0] += 1
        cache = cache.filter { $0.value.providerID != providerID || (collectionID != nil && $0.value.collectionID != collectionID) }
        providers[providerID]?.invalidate?(collectionID)
    }
    func invalidateRemote(_ providerID: String) { invalidate(providerID: providerID) }
    func removeAll() { for id in Array(providers.keys) { invalidateRemote(id) } }

    func isFresh(_ url: URL, for track: Track) -> Bool {
        if url.isFileURL {
            guard FileManager.default.isReadableFile(atPath: url.path) else { return false }
            if localURL(for: track) == url { return true }
            if let key = audioCacheKey(for: track), AudioPlaybackCache.shared.file(for: key) == url { return true }
            if url.deletingLastPathComponent().standardizedFileURL.path == AudioPlaybackCache.shared.directory.standardizedFileURL.path { return false }
        }
        guard let cached = cache[track.id], cached.source.url == url else { return false }
        return cached.source.expiresAt.timeIntervalSince(now()) > Self.refreshMargin
    }
}

nonisolated enum PlaybackError: LocalizedError, Equatable {
    case unavailable
    case failed
    case localUnavailable

    var errorDescription: String? {
        switch self {
        case .unavailable: String(localized: "这首曲目暂时无法播放")
        case .localUnavailable: String(localized: "本地音频无法访问，请检查文件是否存在并重新授权扫描目录")
        case .failed: String(localized: "播放失败，请稍后重试")
        }
    }
}
