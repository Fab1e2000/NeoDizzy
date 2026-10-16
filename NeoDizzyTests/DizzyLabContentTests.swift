import Foundation
import Testing
@testable import NeoDizzy

@MainActor
struct DizzyLabContentTests {
    @Test func remembersListArtworkAndReusesDetailUntilAccountChanges() {
        let cache = DizzyLabContentCache(prepareArtwork: { _ in })
        let url = URL(string: "https://example.invalid/cover.jpg")!
        cache.remember([DiscSummary(id: "album", title: "Album", coverURL: url)])
        #expect(cache.artwork(for: "album") == url)
        let detail = cache.disc("album")
        #expect(cache.disc("album") === detail)
        let oldFeed = cache.feed
        let oldLibrary = cache.library
        cache.accountChanged()
        #expect(cache.disc("album") !== detail)
        #expect(cache.feed !== oldFeed && cache.library !== oldLibrary)
        #expect(cache.artwork(for: "album") == url)
    }

    @Test func firstPageCallbackSeedsAlbumWithoutLoadingItsDetail() async {
        let cache = DizzyLabContentCache(prepareArtwork: { _ in })
        let summary = DiscSummary(id: "album", title: "Album", coverURL: URL(string: "https://example.invalid/cover.jpg"))
        let list = PagedList { _ in Page(items: [summary], hasMore: false) }
        list.didLoad = { cache.remember($0) }
        await list.loadMore()
        #expect(cache.artwork(for: "album") == summary.coverURL)
        #expect(cache.disc("album").detail.value == nil)
    }
}
