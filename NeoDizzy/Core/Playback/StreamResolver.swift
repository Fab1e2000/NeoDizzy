import Foundation

/// 播放地址带时间签名，约一小时后过期（见 `DizzyURL.streamExpiry`），所以只在即将播放时获取。
/// 同一张专辑的地址一次请求全部拿到，按专辑缓存。
final class StreamResolver {
    /// 距离过期不到这么久就重新获取，避免播到一半地址失效。
    static let refreshMargin: TimeInterval = 120

    private var cache: [String: [String: URL]] = [:]
    private let fetch: (String) async throws -> [String: URL]
    private let now: () -> Date

    init(
        fetch: @escaping (String) async throws -> [String: URL] = { try await DizzyAPI.shared.discDetail(id: $0).streams },
        now: @escaping () -> Date = Date.init
    ) {
        self.fetch = fetch
        self.now = now
    }

    /// 专辑页已经拿到的地址，直接放进缓存，播放时不用再请求一次。
    func store(_ streams: [String: URL], for discID: String) {
        guard !streams.isEmpty else { return }
        cache[discID] = streams
    }

    func stream(for track: Track) async throws -> URL {
        if let url = cache[track.discID]?[track.number], isFresh(url) {
            return url
        }
        let streams = try await fetch(track.discID)
        cache[track.discID] = streams
        guard let url = streams[track.number] else {
            throw PlaybackError.unavailable
        }
        return url
    }

    /// 播放出错（多半是地址过期返回 403）后丢掉这张专辑的地址，下次重新获取。
    func invalidate(discID: String) {
        cache[discID] = nil
    }

    /// 登录或退出登录后，同一张专辑的地址可能从试听变成完整版（或反过来），全部重新获取。
    func removeAll() {
        cache.removeAll()
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

    var errorDescription: String? {
        switch self {
        case .unavailable: String(localized: "这首曲目暂时无法播放")
        case .failed: String(localized: "播放失败，请稍后重试")
        }
    }
}
