import Foundation
import SwiftUI
import Testing
@testable import NeoDizzy

@MainActor struct DizzyLabCacheLifecycleTests {
    @Test func removingDizzyCacheStopsRemainingArtworkBatches() async {
        var release: CheckedContinuation<Void, Never>?
        var batches = 0
        let cache = DizzyLabContentCache(prepareArtwork: { _ in
            batches += 1
            await withCheckedContinuation { release = $0 }
        })
        cache.remember((0..<8).map { DiscSummary(id: String($0), title: "Disc", coverURL: URL(string: "https://example.invalid/\($0).jpg")) })
        while release == nil { await Task.yield() }
        cache.stop()
        release?.resume()
        cache.remember([DiscSummary(id: "later", title: "Later", coverURL: URL(string: "https://example.invalid/later.jpg"))])
        for _ in 0..<5 { await Task.yield() }
        #expect(batches == 1)
    }
}
