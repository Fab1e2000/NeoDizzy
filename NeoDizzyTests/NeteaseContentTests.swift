import Foundation
import Synchronization
import Testing
@testable import NeoDizzy

@MainActor
@Suite(.serialized)
struct NeteaseContentTests {
    @Test func sharesPageAndSeedsDetailBeforeItsRequestThenClearsOnAccountChange() throws {
        let cache = NeteaseContentCache(prepareArtwork: { _ in })
        let home = cache.page(.home("", 1000), revision: 1)
        #expect(home === cache.page(.home("", 1000), revision: 1))
        home.playlists = [try JSONDecoder().decode(NeteasePlaylist.self, from: Data(#"{"id":7,"name":"Playlist","coverImgUrl":"https://p1.music.126.net/test.jpg"}"#.utf8))]
        home.didUpdate?(home)
        let detail = cache.page(.route(.playlist(7)), revision: 1)
        #expect(detail.title == "Playlist")
        #expect(detail.artwork == home.playlists[0].artworkURL)
        #expect(!detail.hasLoaded)
        let replacement = cache.page(.route(.playlist(7)), revision: 2)
        #expect(replacement !== detail && replacement.title.isEmpty)
        home.didUpdate?(home)
        #expect(replacement.title.isEmpty)
    }

    @Test func concurrentNavigationReusesRequestAndEmbeddedPlaylistSongs() async {
        let count = Mutex(0)
        ContentStub.handler = { request in
            count.withLock { $0 += 1 }
            #expect(request.url?.path == "/eapi/v6/playlist/detail")
            return #"{"code":200,"playlist":{"id":7,"name":"Playlist","trackIds":[{"id":42}],"tracks":[{"id":42,"name":"Song","ar":[],"al":{"id":1,"name":"Album"}}]}}"#
        }
        let api = makeAPI()
        let model = NeteasePageModel()
        async let first: Void = model.load(api: api, route: .playlist(7))
        async let second: Void = model.load(api: api, route: .playlist(7))
        _ = await (first, second)
        #expect(count.withLock { $0 } == 1)
        #expect(model.hasLoaded && model.songs.count == 1 && !model.more)
    }

    @Test func playlistPublishesHeaderBeforeFetchingMissingTracks() async {
        ContentStub.handler = { request in
            if request.url?.path == "/eapi/v6/playlist/detail" {
                return #"{"code":200,"playlist":{"id":7,"name":"Ready Header","trackIds":[{"id":42}]}}"#
            }
            return #"{"code":200,"songs":[{"id":42,"name":"Song","ar":[]}]}"#
        }
        let model = NeteasePageModel()
        var sawHeaderBeforeSongs = false
        model.didUpdate = { page in
            if page.title == "Ready Header" && page.songs.isEmpty { sawHeaderBeforeSongs = true }
        }
        await model.load(api: makeAPI(), route: .playlist(7))
        #expect(sawHeaderBeforeSongs)
        #expect(model.songs.count == 1 && model.hasLoaded)
    }

    @Test func skeletonCoversFirstFrameButNotLoadedEmptyResultsErrorsOrRetainedContent() async throws {
        let model = NeteasePageModel()
        #expect(model.showsInitialSkeleton)
        model.error = "请求失败"
        #expect(!model.showsInitialSkeleton)
        model.reset()
        ContentStub.handler = { _ in #"{"code":200,"list":[]}"# }
        await model.load(api: makeAPI(), route: .charts)
        #expect(model.hasLoaded && model.isEmpty)
        #expect(!model.showsInitialSkeleton)
        model.loading = true
        #expect(model.showsInitialSkeleton)
        model.playlists = [try JSONDecoder().decode(NeteasePlaylist.self, from: Data(#"{"id":7,"name":"Playlist"}"#.utf8))]
        #expect(!model.showsInitialSkeleton)
    }

    private func makeAPI() -> NeteaseAPI {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [ContentStub.self]
        return NeteaseAPI(client: NeteaseClient(session: URLSession(configuration: configuration)))
    }
}

nonisolated private final class ContentStub: URLProtocol, @unchecked Sendable {
    nonisolated(unsafe) static var handler: (@Sendable (URLRequest) -> String)?
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        guard let url = request.url, let handler = Self.handler else { return }
        client?.urlProtocol(self, didReceive: HTTPURLResponse(url: url, statusCode: 200, httpVersion: nil, headerFields: nil)!, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: Data(handler(request).utf8))
        client?.urlProtocolDidFinishLoading(self)
    }
    override func stopLoading() {}
}
