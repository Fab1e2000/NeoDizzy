import Foundation
import Synchronization
import Testing
@testable import NeoDizzy

@Suite(.serialized) @MainActor
struct QQMusicBrowseTests {
    @Test func typedSearchParsesActualResponseAliasesAndRemovesHighlightMarkup() throws {
        let album = try QQMusicClient.typedSearch(data(.albums, rows: [["albummid": "albumMid", "id": 123, "name": "<em>专辑</em>", "singer": "歌手", "publish_date": "2026-10-23"]]), kind: .albums, page: 1)
        #expect(album.albums.first?.id == "albumMid" && album.albums.first?.title == "专辑")
        #expect(album.albums.first?.artist == "歌手" && album.nextPage == 2)
        let artist = try QQMusicClient.typedSearch(data(.artists, rows: [["singerMID": "artistMid", "singerID": 123, "singerName": "歌手", "singerPic": "http://example.com/artist.jpg"]], next: -1), kind: .artists, page: 1)
        #expect(artist.artists.first?.id == "artistMid" && artist.nextPage == nil)
        #expect(artist.artists.first?.coverURL?.scheme == "https")
        let playlists = try QQMusicClient.typedSearch(data(.playlists, rows: [["dissid": "9007199254740993", "dissname": "<em>收藏</em> &amp; 音乐", "logo": "https://example.com/cover.jpg"]]), kind: .playlists, page: 1)
        #expect(playlists.playlists.first?.id == "9007199254740993")
        #expect(playlists.playlists.first?.title == "收藏 & 音乐")
    }

    @Test func malformedTypedResultsAreErrorsAndRepeatedOrBackwardCursorStops() throws {
        #expect(throws: QQMusicError.self) { try QQMusicClient.typedSearch(["body": ["item_album": []]], kind: .albums, page: 1) }
        #expect(throws: QQMusicError.self) { try QQMusicClient.typedSearch(data(.artists, rows: [["singerName": "No MID"]]), kind: .artists, page: 1) }
        #expect(try QQMusicClient.typedSearch(data(.songs, rows: [], next: 2), kind: .songs, page: 1).nextPage == nil)
        #expect(try QQMusicClient.typedSearch(data(.songs, rows: [["mid": "s", "title": "Song"]], next: 1), kind: .songs, page: 1).nextPage == nil)
    }

    @Test func typedSearchUsesModuleKeyedEnvelopeWithoutWebCommAndPreservesSessionCookies() async throws {
        QQBrowseStub.state.withLock { $0 = .init(replies: [data(.artists, rows: [["singerMID": "artist", "singerName": "Artist"]], next: -1)]) }
        let client = makeClient(credential: .init(musicID: "123", musicKey: "synthetic-key"))
        let result = try await client.search(query: "Artist", kind: .artists)
        #expect(result.artists.count == 1)
        let request = try #require(QQBrowseStub.state.withLock { $0.requests.first })
        let body = try #require(try JSONSerialization.jsonObject(with: request.body) as? [String: Any])
        #expect(Set(body.keys) == ["music.search.SearchCgiService"])
        let call = try #require(body["music.search.SearchCgiService"] as? [String: Any])
        #expect(call["method"] as? String == "DoSearchForQQMusicMobile")
        let param = try #require(call["param"] as? [String: Any])
        #expect(param["search_type"] as? Int == 1 && param["page_num"] as? Int == 1)
        #expect(request.cookie?.contains("qqmusic_key=synthetic-key") == true)
    }

    @Test func albumSearchFollowsServerNextPageAndStopsWhenPageRepeats() async throws {
        let rows: [[String: Any]] = [["albummid": "a", "name": "A"], ["albummid": "b", "name": "B"]]
        QQBrowseStub.state.withLock { $0 = .init(replies: [data(.albums, rows: rows, next: 4), data(.albums, rows: rows, next: 5)]) }
        let store = QQMusicStore(restoreSaved: false, api: makeClient(), saveCredential: { _ in }), model = QQMusicPageModel()
        await model.load(store: store, route: .typedSearch("query", .albums))
        #expect(model.albums.count == 2 && model.more)
        await model.load(store: store, route: .typedSearch("query", .albums), append: true)
        #expect(model.albums.count == 2 && !model.more)
        let calls = QQBrowseStub.state.withLock { $0.requests }
        let body = try #require(try JSONSerialization.jsonObject(with: calls[1].body) as? [String: Any])
        let call = try #require(body["music.search.SearchCgiService"] as? [String: Any])
        #expect((call["param"] as? [String: Any])?["page_num"] as? Int == 4)
    }

    @Test func failedRefreshPreservesDirectoryAndKindSwitchClearsPreviousResults() async {
        QQBrowseStub.state.withLock { $0 = .init(replies: [data(.albums, rows: [["albummid": "a", "name": "A"]]), ["body": [:]], data(.artists, rows: [["singerMID": "s", "singerName": "S"]], next: -1)]) }
        let store = QQMusicStore(restoreSaved: false, api: makeClient(), saveCredential: { _ in }), model = QQMusicPageModel()
        await model.load(store: store, route: .typedSearch("q", .albums))
        await model.load(store: store, route: .typedSearch("q", .albums))
        #expect(model.albums.count == 1 && model.error != nil)
        await model.load(store: store, route: .typedSearch("q", .artists))
        #expect(model.albums.isEmpty && model.artists.count == 1 && model.error == nil)
    }

    @Test func singerAlbumPaginationAdvancesByActualRawCountIncludingDuplicates() async throws {
        QQBrowseStub.state.withLock { $0 = .init(replies: [
            ["albumList": [["albumMid": "a", "albumName": "A"], ["albumMid": "a", "albumName": "A"]], "total": 3],
            ["albumList": [["albumMid": "b", "albumName": "B"]], "total": 3]
        ]) }
        let store = QQMusicStore(restoreSaved: false, api: makeClient(), saveCredential: { _ in }), model = QQMusicPageModel()
        await model.load(store: store, route: .artistAlbums("s"))
        #expect(model.albums.count == 1 && model.more)
        await model.load(store: store, route: .artistAlbums("s"), append: true)
        #expect(model.albums.map(\.id) == ["a", "b"] && !model.more)
        let calls = QQBrowseStub.state.withLock { $0.requests }
        let body = try #require(try JSONSerialization.jsonObject(with: calls[1].body) as? [String: Any])
        let call = try #require(body["req_0"] as? [String: Any])
        #expect((call["param"] as? [String: Any])?["begin"] as? Int == 2)
    }

    @Test func albumUsesTrackOrderWhileSongIdentifiersRemainStable() async {
        QQBrowseStub.state.withLock { $0 = .init(replies: [
            ["basicInfo": ["name": "Album"]],
            ["songList": [
                ["songInfo": ["mid": "second", "title": "Second", "index_album": 2]],
                ["songInfo": ["mid": "first", "title": "First", "index_album": 1]]
            ], "totalNum": 2]
        ]) }
        let store = QQMusicStore(restoreSaved: false, api: makeClient(), saveCredential: { _ in }), model = QQMusicPageModel()
        await model.load(store: store, route: .album("album"))
        #expect(model.songs.map(\.mid) == ["first", "second"])
        #expect(model.error == nil)
    }

    @Test func songRetainsArtistIdentityAndTrackMetadata() throws {
        let song = try QQMusicSong(json: ["id": 123, "mid": "song", "title": "Song", "type": 0, "index_album": 7, "index_cd": 0,
                                         "singer": [["mid": "artist", "name": "Artist"]]])
        #expect(song.singers.first?.id == "artist" && song.singers.first?.name == "Artist")
        #expect(song.trackNumber == 7 && song.discNumber == nil && song.songType == 0)
        #expect(song.track.number == "song")
    }

    private func data(_ kind: QQMusicSearchKind, rows: [[String: Any]], next: Int = 2) -> [String: Any] {
        ["body": [kind.responseKey: rows], "meta": ["nextpage": next]]
    }
    private func makeClient(credential: QQMusicCredential? = nil) -> QQMusicClient {
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [QQBrowseStub.self]
        return QQMusicClient(session: URLSession(configuration: config), credential: credential)
    }
}

nonisolated private final class QQBrowseStub: URLProtocol, @unchecked Sendable {
    struct Request { let body: Data; let cookie: String? }
    struct State { var replies: [[String: Any]] = []; var requests: [Request] = [] }
    static let state = Mutex(State())
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        var body = request.httpBody ?? Data()
        if let stream = request.httpBodyStream {
            stream.open(); defer { stream.close() }
            var buffer = [UInt8](repeating: 0, count: 4096)
            while stream.hasBytesAvailable { let count = stream.read(&buffer, maxLength: buffer.count); if count <= 0 { break }; body.append(contentsOf: buffer.prefix(count)) }
        }
        let reply = Self.state.withLock { state in
            let index = state.requests.count
            state.requests.append(Request(body: body, cookie: request.value(forHTTPHeaderField: "Cookie")))
            return index < state.replies.count ? state.replies[index] : [:]
        }
        let object = (try? JSONSerialization.jsonObject(with: body)) as? [String: Any] ?? [:]
        let key = object["music.search.SearchCgiService"] != nil ? "music.search.SearchCgiService" : "req_0"
        let data = try! JSONSerialization.data(withJSONObject: ["code": 0, key: ["code": 0, "data": reply]])
        client?.urlProtocol(self, didReceive: HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: data)
        client?.urlProtocolDidFinishLoading(self)
    }
    override func stopLoading() {}
}
