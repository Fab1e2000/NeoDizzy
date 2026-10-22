import Foundation

nonisolated struct RemotePlaybackSource {
    let url: URL
    let expiresAt: Date
    let isPreview: Bool
    var actualQuality: String? = nil
    var fileExtension: String? = nil
}

/// 本地文件、DizzyLab 专辑地址和注册来源的逐曲播放地址分别解析与缓存。
final class StreamResolver {
    private var remoteProviders: [String: (String) async throws -> RemotePlaybackSource] = [:]
    private var lyricProviders: [String: (String) async throws -> LocalLyrics] = [:]
    private var remoteCache: [String: RemotePlaybackSource] = [:]
    private var cacheKeys: [String: (Track) -> AudioPlaybackCache.Key] = [:]
    private var revisions: [String: Int] = [:]

    func register(_ provider: String, stream: @escaping (String) async throws -> RemotePlaybackSource,
                  lyrics: @escaping (String) async throws -> LocalLyrics,
                  cacheKey: ((Track) -> AudioPlaybackCache.Key)? = nil) {
        cacheKeys[provider] = cacheKey
        remoteProviders[provider] = stream
        lyricProviders[provider] = lyrics
    }
    func audioCacheKey(for track: Track) -> AudioPlaybackCache.Key? {
        if let source = track.remoteSource { return cacheKeys[source.providerID]?(track) }
        guard track.localSource == nil else { return nil }
        return .init(trackID: track.id,
                     scope: AudioPlaybackCache.digest(DizzyHTTPClient.shared.credentials.cookieHeader() ?? ""), quality: "original")
    }
    func actualQuality(for track: Track) -> String? {
        track.remoteSource == nil ? "original" : remoteCache[track.id]?.actualQuality
    }

    func lyrics(for track: Track) async throws -> LocalLyrics? {
        guard let source = track.remoteSource, let fetch = lyricProviders[source.providerID] else { return nil }
        return try await fetch(source.itemID)
    }
    func isPreview(for track: Track?, url: URL) -> Bool {
        if url.isFileURL { return false }
        if let track, track.remoteSource != nil { return remoteCache[track.id]?.isPreview ?? false }
        return DizzyURL.isPreviewStream(url)
    }
    func invalidate(for track: Track) {
        if track.remoteSource != nil { remoteCache[track.id] = nil }
        else { invalidate(discID: track.discID) }
    }

    /// 距离过期不到这么久就重新获取，避免播到一半地址失效。
    static let refreshMargin: TimeInterval = 120

    private var cache: [String: [String: URL]] = [:]
    private var dizzyRevision = 0
    private let fetch: (String) async throws -> [String: URL]
    private let now: () -> Date
    private var retainedAccess: OfflineFolderAccess?
    private let localAccess: (Track) -> OfflineFolderAccess?
    private let localFile: (Track) -> URL?

    init(
        fetch: @escaping (String) async throws -> [String: URL] = { try await DizzyAPI.shared.discDetail(id: $0, fresh: true).streams },
        now: @escaping () -> Date = Date.init,
        localFile: @escaping (Track) -> URL? = { _ in nil },
        localAccess: @escaping (Track) -> OfflineFolderAccess? = { _ in nil }
    ) {
        self.fetch = fetch
        self.now = now
        self.localFile = localFile
        self.localAccess = localAccess
    }

    func localURL(for track: Track) -> URL? { localFile(track) }
    func releaseLocalAccess() { retainedAccess = nil }

    /// 专辑页已经拿到的地址，直接放进缓存，播放时不用再请求一次。
    func store(_ streams: [String: URL], for discID: String) {
        guard !streams.isEmpty else { return }
        cache[discID] = streams
    }

    func stream(for track: Track, preferLocal: Bool = true, retainAccess: Bool = true) async throws -> URL {
        // 每次换曲目都重新查询：刚下载的曲目立即可播，移走的文件可回退到串流。
        // 本地地址不放入签名地址缓存，也不受登录/退出登录的缓存清理影响。
        if (preferLocal || track.localSource != nil), let url = localFile(track), url.isFileURL,
           FileManager.default.isReadableFile(atPath: url.path) {
            if retainAccess { retainedAccess = localAccess(track) }
            return url
        }
        if preferLocal, let key = audioCacheKey(for: track), let file = AudioPlaybackCache.shared.file(for: key) {
            return file
        }
        if track.localSource != nil { throw PlaybackError.localUnavailable }
        if retainAccess { retainedAccess = nil }
        if let source = track.remoteSource {
            if retainAccess { retainedAccess = nil }
            if let cached = remoteCache[track.id], cached.expiresAt.timeIntervalSince(now()) > Self.refreshMargin { return cached.url }
            guard let provider = remoteProviders[source.providerID] else { throw PlaybackError.unavailable }
            let generation = revisions[source.providerID, default: 0]
            let result = try await provider(source.itemID)
            try Task.checkCancellation()
            guard generation == revisions[source.providerID, default: 0] else { throw CancellationError() }
            remoteCache[track.id] = result
            return result.url
        }
        if let url = cache[track.discID]?[track.number], isFresh(url) {
            return url
        }
        let revision = dizzyRevision
        let streams = try await fetch(track.discID)
        try Task.checkCancellation()
        guard revision == dizzyRevision else { throw CancellationError() }
        cache[track.discID] = streams
        guard let url = streams[track.number] else {
            throw PlaybackError.unavailable
        }
        return url
    }

    /// 播放出错（多半是地址过期返回 403）后丢掉这张专辑的地址，下次重新获取。
    func invalidate(discID: String) {
        dizzyRevision += 1
        cache[discID] = nil
    }

    /// 登录或退出登录后，同一张专辑的地址可能从试听变成完整版（或反过来），全部重新获取。
    func removeAll() {
        for provider in remoteProviders.keys { invalidateRemote(provider) }
        remoteCache.removeAll()
        clearDizzyLabCache()
    }

    func invalidateRemote(_ providerID: String) {
        revisions[providerID, default: 0] += 1
        remoteCache = remoteCache.filter { !$0.key.hasPrefix("remote/\(providerID)/") }
    }

    func clearDizzyLabCache() { dizzyRevision += 1; cache.removeAll() }

    func isFresh(_ url: URL, for track: Track) -> Bool {
        if url.isFileURL {
            guard FileManager.default.isReadableFile(atPath: url.path) else { return false }
            if localFile(track) == url { return true }
            if let key = audioCacheKey(for: track), AudioPlaybackCache.shared.file(for: key) == url { return true }
            // A remote provider may return a file URL in tests; it still obeys source invalidation.
            if url.deletingLastPathComponent().standardizedFileURL.path == AudioPlaybackCache.shared.directory.standardizedFileURL.path { return false }
        }
        if track.remoteSource != nil {
            guard let source = remoteCache[track.id], source.url == url else { return false }
            return source.expiresAt.timeIntervalSince(now()) > Self.refreshMargin
        }
        return isFresh(url)
    }

    private func isFresh(_ url: URL) -> Bool {
        // 看不出过期时间时照常使用，真的失效了会在播放出错后重新获取。
        guard let expiry = DizzyURL.streamExpiry(url) else { return true }
        return expiry.timeIntervalSince(now()) > Self.refreshMargin
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
