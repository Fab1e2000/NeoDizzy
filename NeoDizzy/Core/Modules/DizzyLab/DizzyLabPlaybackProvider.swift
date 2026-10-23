import Foundation

/// DizzyLab's album-wide signed URLs are adapted to the same per-track contract
/// used by every other source. No network source is installed by the host implicitly.
final class DizzyLabPlaybackProvider {
    private var albums: [String: [String: URL]] = [:]
    private var revision = 0
    private let fetch: (String) async throws -> [String: URL]
    private let now: () -> Date

    init(fetch: @escaping (String) async throws -> [String: URL] = { try await DizzyAPI.shared.discDetail(id: $0, fresh: true).streams },
         now: @escaping () -> Date = Date.init) {
        self.fetch = fetch
        self.now = now
    }

    var provider: PlaybackProvider {
        PlaybackProvider(stream: { [self] track in try await resolve(track) }, cacheKey: { track in
            .init(trackID: track.id, scope: AudioPlaybackCache.digest(DizzyHTTPClient.shared.credentials.cookieHeader() ?? ""), quality: "original")
        }, prime: { [self] streams, album in albums[album] = streams }, invalidate: { [self] album in
            revision += 1
            if let album { albums[album] = nil } else { albums.removeAll() }
        })
    }

    private func resolve(_ track: Track) async throws -> RemotePlaybackSource {
        if let url = albums[track.discID]?[track.number], fresh(url) { return source(url) }
        let generation = revision
        let streams = try await fetch(track.discID)
        try Task.checkCancellation()
        guard generation == revision else { throw CancellationError() }
        albums[track.discID] = streams
        guard let url = streams[track.number] else { throw PlaybackError.unavailable }
        return source(url)
    }
    private func source(_ url: URL) -> RemotePlaybackSource {
        .init(url: url, expiresAt: DizzyURL.streamExpiry(url) ?? .distantFuture,
              isPreview: DizzyURL.isPreviewStream(url), actualQuality: "original", fileExtension: url.pathExtension)
    }
    private func fresh(_ url: URL) -> Bool {
        (DizzyURL.streamExpiry(url) ?? .distantFuture).timeIntervalSince(now()) > StreamResolver.refreshMargin
    }
}
