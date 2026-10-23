import Foundation
import SwiftUI
import Testing
@testable import NeoDizzy

@MainActor struct NeteaseCacheLifecycleTests {
    @Test func removedNeteaseCacheRejectsLatePageCallbacks() async {
        var batches = 0
        let cache = NeteaseContentCache(prepareArtwork: { _ in batches += 1 })
        let oldPage = cache.page(.route(.album(1)), revision: 0)
        cache.stop()
        oldPage.artwork = URL(string: "https://example.invalid/old.jpg")
        oldPage.didUpdate?(oldPage)
        for _ in 0..<5 { await Task.yield() }
        #expect(batches == 0)
    }
}
