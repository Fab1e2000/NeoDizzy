import Foundation
import Testing
@testable import NeoDizzy

private func track(_ number: Int, disc: String = "fx4") -> Track {
    Track(discID: disc, number: String(number), title: "Track \(number)", artists: "", albumTitle: "", coverURL: nil)
}

struct DizzyLabStreamResolverTests {
    /// 过期时间 2026-09-26 17:38（东八区）。
    private let signed = URL(string: "https://streaming.dizzylab.net/202609261738/47b9396aaf5e70bc3fc219be690419bd/fx4/preview/1.mp3")!
    private let renewed = URL(string: "https://streaming.dizzylab.net/202609261838/0f0f0f0f0f0f0f0f0f0f0f0f0f0f0f0f/fx4/preview/1.mp3")!
    private var expiry: Date { DizzyURL.streamExpiry(signed)! }

    private final class FetchLog {
        var discIDs: [String] = []
    }

    private func resolver(now: Date, log: FetchLog, result: [String: URL]) -> StreamResolver {
        let resolver = StreamResolver(now: { now })
        resolver.register("dizzylab", provider: DizzyLabPlaybackProvider(fetch: { discID in
            log.discIDs.append(discID)
            return result
        }, now: { now }).provider)
        return resolver
    }

    @Test func usesAddressFromDiscPageWhileFresh() async throws {
        let log = FetchLog()
        let resolver = resolver(now: expiry.addingTimeInterval(-600), log: log, result: ["1": renewed])
        resolver.prime(["1": signed], providerID: "dizzylab", collectionID: "fx4")
        #expect(try await resolver.stream(for: track(1)) == signed)
        #expect(log.discIDs.isEmpty)
    }

    @Test func refetchesShortlyBeforeExpiry() async throws {
        let log = FetchLog()
        let resolver = resolver(now: expiry.addingTimeInterval(-60), log: log, result: ["1": renewed])
        resolver.prime(["1": signed], providerID: "dizzylab", collectionID: "fx4")
        #expect(try await resolver.stream(for: track(1)) == renewed)
        #expect(log.discIDs == ["fx4"])
    }

    @Test func refetchesAfterPlaybackFailure() async throws {
        let log = FetchLog()
        let resolver = resolver(now: expiry.addingTimeInterval(-600), log: log, result: ["1": renewed])
        resolver.prime(["1": signed], providerID: "dizzylab", collectionID: "fx4")
        resolver.invalidate(providerID: "dizzylab", collectionID: "fx4")
        #expect(try await resolver.stream(for: track(1)) == renewed)
        #expect(log.discIDs == ["fx4"])
    }

    @Test func missingTrackIsUnavailable() async {
        let resolver = resolver(now: expiry, log: FetchLog(), result: ["1": renewed])
        await #expect(throws: PlaybackError.unavailable) {
            try await resolver.stream(for: track(7))
        }
    }

}
