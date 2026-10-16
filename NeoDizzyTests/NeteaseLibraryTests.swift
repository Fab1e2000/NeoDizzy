import CommonCrypto
import Foundation
import Synchronization
import Testing
@testable import NeoDizzy

@Suite(.serialized) @MainActor struct NeteaseLibraryTests {
    private func api() -> NeteaseAPI {
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [LibraryStub.self]
        let client = NeteaseClient(session: URLSession(configuration: config), checkTokenProvider: { "fresh-test-token" })
        client.cookie = "MUSIC_U=test-account; __csrf=test-csrf; unrelated=must-not-send"
        return NeteaseAPI(client: client)
    }
    private func playlist(_ id: Int = 7, owner: Int = 2, subscribed: Bool = false) throws -> NeteasePlaylist {
        try JSONDecoder().decode(NeteasePlaylist.self, from: Data("{\"id\":\(id),\"name\":\"List\",\"subscribed\":\(subscribed),\"creator\":{\"userId\":\(owner),\"nickname\":\"User\"}}".utf8))
    }
    private func waitFor(_ test: () -> Bool) async throws {
        for _ in 0..<200 { if test() { return }; try await Task.sleep(for: .milliseconds(10)) }
        Issue.record("Timed out waiting for request")
    }
    @Test func favoriteSyncUsesOwnedPlaylistAndPreservesItsOrder() async throws {
        LibraryStub.handler = { request in
            switch request.url?.path {
            case "/eapi/user/playlist":
                return .init(body: #"{"code":200,"playlist":[{"id":8,"name":"Other","specialType":5,"creator":{"userId":2,"nickname":"Other"}},{"id":7,"name":"Renamed","specialType":5,"creator":{"userId":1,"nickname":"Me"}}]}"#)
            case "/eapi/v6/playlist/detail":
                let body = try decodeEAPI(request)
                #expect(body["id"] as? Int == 7)
                return .init(body: #"{"code":200,"playlist":{"id":7,"name":"Liked","trackCount":2,"trackIds":[{"id":90},{"id":1}],"tracks":[{"id":1,"name":"Stale embedded"}]}}"#)
            case "/eapi/v3/song/detail":
                return .init(body: #"{"code":200,"songs":[{"id":1,"name":"One","no":1},{"id":90,"name":"Ninety","no":9}]}"#)
            default:
                Issue.record("Unexpected endpoint: \(request.url?.path ?? "")")
                return .init(body: #"{"code":500}"#)
            }
        }
        let songs = try await api().favoritePlaylistSongs(userID: 1)
        #expect(songs.map(\.id) == [90, 1])
    }
    @Test func favoriteSyncRejectsMissingPlaylistAndIncompleteSongs() async throws {
        LibraryStub.handler = { _ in .init(body: #"{"code":200,"playlist":[]}"#) }
        await #expect(throws: (any Error).self) { try await api().favoritePlaylistSongs(userID: 1) }
        LibraryStub.handler = { request in
            switch request.url?.path {
            case "/eapi/user/playlist":
                return .init(body: #"{"code":200,"playlist":[{"id":7,"name":"Liked","specialType":5,"creator":{"userId":1,"nickname":"Me"}}]}"#)
            case "/eapi/v6/playlist/detail":
                return .init(body: #"{"code":200,"playlist":{"id":7,"name":"Liked","trackCount":1,"trackIds":[{"id":90}]}}"#)
            default: return .init(body: #"{"code":200,"songs":[]}"#)
            }
        }
        await #expect(throws: (any Error).self) { try await api().favoritePlaylistSongs(userID: 1) }
    }
    @Test func likesCommitOnlyAfterSuccessAndUseOfficialParameters() async throws {
        let succeeds = Mutex(false)
        LibraryStub.handler = { request in
            if request.url?.path == "/eapi/song/like/get" { return .init(body: #"{"code":200,"ids":[1]}"#) }
            let body = try decodeEAPI(request)
            #expect(request.url?.path == "/eapi/radio/like")
            #expect(body["trackId"] as? Int == 42)
            #expect(body["like"] as? Bool == true)
            #expect(body["alg"] as? String == "itembased")
            #expect(body["time"] as? String == "3")
            return .init(body: succeeds.withLock { $0 } ? #"{"code":200}"# : #"{"code":403}"#)
        }
        let library = NeteaseLibrary(api: api()); library.reset(userID: 1)
        do { try await library.toggleLike(42); Issue.record("Write should fail") } catch { }
        #expect(library.likedIDs == [1]); #expect(library.pending.isEmpty)
        succeeds.withLock { $0 = true }
        try await library.toggleLike(42)
        #expect(library.likedIDs == [1, 42]); #expect(library.orderedLikedIDs.first == 42)
    }
    @Test func duplicateWritesCoalesceAndUnlikeRemovesSong() async throws {
        let count = Mutex(0)
        LibraryStub.handler = { request in
            if request.url?.path == "/eapi/song/like/get" { return .init(body: #"{"code":200,"ids":[]}"#) }
            count.withLock { $0 += 1 }
            return .init(body: #"{"code":200}"#, delay: 0.08)
        }
        let library = NeteaseLibrary(api: api()); library.reset(userID: 1)
        try await library.loadLikes()
        async let first: Void = library.toggleLike(42)
        async let second: Void = library.toggleLike(42)
        _ = try await (first, second)
        #expect(count.withLock { $0 } == 1); #expect(library.likedIDs == [42])
        try await library.toggleLike(42)
        #expect(library.likedIDs.isEmpty && library.orderedLikedIDs.isEmpty)
    }
    @Test func playlistSubscriptionAppearsInLibraryAndCannotUnsubscribeOwnList() async throws {
        let paths = Mutex<[String]>([])
        LibraryStub.handler = { request in
            let path = request.url!.path; paths.withLock { $0.append(path) }
            #expect(request.httpMethod == "POST")
            #expect(request.url?.host == "music.163.com")
            #expect(request.value(forHTTPHeaderField: "Cookie")?.contains("MUSIC_U=test-account") == true)
            #expect(request.value(forHTTPHeaderField: "Cookie")?.contains("X-antiCheatToken") == false)
            #expect(request.value(forHTTPHeaderField: "Cookie")?.contains("unrelated") == false)
            return .init(body: #"{"code":200}"#)
        }
        let library = NeteaseLibrary(api: api()); library.reset(userID: 1)
        let value = try playlist()
        try await library.togglePlaylist(value)
        #expect(library.playlists.map(\.id) == [7]); #expect(library.isSubscribed(value) == true)
        try await library.togglePlaylist(value)
        #expect(library.playlists.isEmpty); #expect(library.isSubscribed(value) == false)
        try await library.togglePlaylist(playlist(owner: 1))
        #expect(paths.withLock { $0 } == ["/weapi/playlist/subscribe", "/weapi/playlist/unsubscribe"])
    }
    @Test func authenticatedWriteProfileMatchesMeloXAndCookiesMatchEncryptedHeader() throws {
        let client = api().client
        let request = try client.makeRequest("/api/playlist/subscribe", data: ["id": 7], authenticated: true, checkToken: "fresh-test-token")
        let header = try #require(decodeEAPI(request)["header"] as? [String: String])
        #expect(header["os"] == "pc")
        #expect(header["appver"] == "3.1.17.204416")
        #expect(header["versioncode"] == "140")
        #expect(header["resolution"] == "1920x1080")
        #expect(header["channel"] == "netease")
        let cookies = NeteaseClient.cookieValues(request.value(forHTTPHeaderField: "Cookie") ?? "")
            .mapValues { $0.removingPercentEncoding ?? $0 }
        #expect(cookies == header.filter { !$0.value.isEmpty })
        #expect(request.value(forHTTPHeaderField: "Cookie")?.contains("mobilename=;") == true)
        #expect(cookies["unrelated"] == nil)
        client.cookie += "; os=android; appver=custom-version; deviceId=account-device"
        let existing = try client.makeRequest("/api/playlist/subscribe", data: [:], authenticated: true)
        let existingHeader = try #require(decodeEAPI(existing)["header"] as? [String: String])
        #expect(existingHeader["os"] == "android")
        #expect(existingHeader["appver"] == "custom-version")
        #expect(existingHeader["deviceId"] == "account-device")
        let publicRequest = try client.makeRequest("/api/search/get", data: [:], authenticated: false)
        #expect((try decodeEAPI(publicRequest)["header"] as? [String: String])?["os"] == "ios")
    }

    @Test func rejectedSubscriptionKeepsStateAndDoesNotRetry() async throws {
        let calls = Mutex(0)
        LibraryStub.handler = { _ in
            calls.withLock { $0 += 1 }
            return .init(body: #"{"code":405,"message":"操作频繁，请稍后再试"}"#)
        }
        let library = NeteaseLibrary(api: api()); library.reset(userID: 1)
        do {
            try await library.togglePlaylist(playlist())
            Issue.record("Rejected write must fail")
        } catch NeteaseError.rejected(let code, let message) {
            #expect(code == 405); #expect(message == "操作频繁，请稍后再试")
        }
        #expect(calls.withLock { $0 } == 1)
        #expect(library.playlists.isEmpty)
        #expect(library.pending.isEmpty)
        #expect(library.isSubscribed(try playlist()) == false)
    }

    @Test func httpRejectionIsDistinctFromAPICode() async throws {
        LibraryStub.handler = { _ in .init(body: "Method Not Allowed", statusCode: 405) }
        do {
            try await api().setPlaylistSubscribed(7, subscribed: true)
            Issue.record("HTTP rejection must fail")
        } catch NeteaseError.httpStatus(let code) {
            #expect(code == 405)
        }
    }

    @Test func explicitCheckTokenRequestsFetchFreshTokensAndSkipPublicReads() async throws {
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [LibraryStub.self]
        var issued = 0
        let client = NeteaseClient(session: URLSession(configuration: config), checkTokenProvider: {
            issued += 1
            return "fresh-\(issued)"
        })
        client.cookie = "MUSIC_U=test-account"
        let tokens = Mutex<[String]>([])
        LibraryStub.handler = { request in
            let payload = try decodeEAPI(request)
            if let token = (payload["header"] as? [String: String])?["X-antiCheatToken"] {
                tokens.withLock { $0.append(token) }
            }
            return .init(body: #"{"code":200}"#)
        }
        struct Status: Decodable { let code: Int }
        let _: Status = try await client.request("/api/playlist/subscribe", data: ["id": 7], authenticated: true, requiresCheckToken: true)
        let _: Status = try await client.request("/api/playlist/unsubscribe", data: ["id": 7], authenticated: true, requiresCheckToken: true)
        let _: Status = try await client.request("/api/search/get")
        #expect(issued == 2)
        #expect(tokens.withLock { $0 } == ["fresh-1", "fresh-2"])
    }

    @Test func tokenFailureOrAccountChangeNeverSubmitsWrite() async throws {
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [LibraryStub.self]
        let requests = Mutex(0)
        LibraryStub.handler = { _ in requests.withLock { $0 += 1 }; return .init(body: #"{"code":200}"#) }
        let failing = NeteaseClient(session: URLSession(configuration: config), checkTokenProvider: { "" })
        failing.cookie = "MUSIC_U=test-account"
        do {
            struct Status: Decodable { let code: Int }
            let _: Status = try await failing.request("/api/playlist/subscribe", authenticated: true, requiresCheckToken: true)
            Issue.record("Empty token must prevent submission")
        } catch NeteaseError.checkTokenUnavailable { }
        var started = false
        let changing = NeteaseClient(session: URLSession(configuration: config), checkTokenProvider: {
            started = true
            try await Task.sleep(for: .milliseconds(100))
            return "old-account-token"
        })
        changing.cookie = "MUSIC_U=test-account"
        struct Status: Decodable { let code: Int }
        let write = Task { let _: Status = try await changing.request("/api/playlist/subscribe", authenticated: true, requiresCheckToken: true) }
        try await waitFor { started }
        changing.cookie = "MUSIC_U=new-account"
        do { try await write.value; Issue.record("Account change must cancel pending write") }
        catch { #expect(error is CancellationError) }
        #expect(requests.withLock { $0 } == 0)
    }

    @Test func websiteSubscriptionDoesNotFetchTokenOrRetryEmptyResponse() async throws {
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [LibraryStub.self]
        let calls = Mutex(0)
        let client = NeteaseClient(session: URLSession(configuration: config), checkTokenProvider: {
            Issue.record("Website subscription must not request a Watchman token")
            throw NeteaseError.checkTokenUnavailable
        })
        client.cookie = "MUSIC_U=test-account; __csrf=test-csrf"
        LibraryStub.handler = { request in
            calls.withLock { $0 += 1 }
            #expect(request.url?.path == "/weapi/playlist/subscribe")
            return .init(body: "")
        }
        do {
            try await NeteaseAPI(client: client).setPlaylistSubscribed(7, subscribed: true)
            Issue.record("Empty response must not be treated as success")
        } catch NeteaseError.emptyResponse { }
        #expect(calls.withLock { $0 } == 1)
    }

    @Test func accountChangeRejectsLateMutation() async throws {
        LibraryStub.handler = { request in
            if request.url?.path == "/eapi/song/like/get" { return .init(body: #"{"code":200,"ids":[]}"#) }
            return .init(body: #"{"code":200}"#, delay: 0.12)
        }
        let api = api(), library = NeteaseLibrary(api: api)
        library.reset(userID: 1); try await library.loadLikes()
        let write = Task { try await library.toggleLike(42) }
        try await waitFor { !library.pending.isEmpty }
        library.reset(userID: 2); api.client.cookie = "MUSIC_U=another-test-account"
        do { try await write.value; Issue.record("Old account write survived") } catch { #expect(error is CancellationError) }
        #expect(library.likedIDs.isEmpty && library.pending.isEmpty && !library.likesLoaded)
    }
    @Test func oldLikeRefreshCannotUndoSuccessfulMutation() async throws {
        let reads = Mutex(0)
        LibraryStub.handler = { request in
            if request.url?.path == "/eapi/song/like/get" {
                let count = reads.withLock { $0 += 1; return $0 }
                return .init(body: #"{"code":200,"ids":[1]}"#, delay: count > 1 ? 0.15 : 0)
            }
            return .init(body: #"{"code":200}"#)
        }
        let library = NeteaseLibrary(api: api()); library.reset(userID: 1)
        try await library.loadLikes()
        let refresh = Task { try await library.loadLikes(force: true) }
        try await waitFor { reads.withLock { $0 } == 2 }
        try await library.toggleLike(42); try await refresh.value
        #expect(library.likedIDs == [1, 42])
    }
    @Test func addSongUsesVersionedRouteAndOnlyRetriesExplicit512() async throws {
        let calls = Mutex(0)
        LibraryStub.handler = { request in
            #expect(request.url?.path == "/eapi/v1/playlist/manipulate/tracks")
            let n = calls.withLock { $0 += 1; return $0 }, body = try decodeEAPI(request)
            #expect(body["op"] as? String == "add"); #expect(body["pid"] as? Int == 7)
            #expect(body["trackIds"] as? String == (n == 1 ? "[\"42\"]" : "[\"42\",\"42\"]"))
            return .init(body: n == 1 ? #"{"code":512}"# : #"{"code":200}"#)
        }
        try await api().addSong(42, to: 7)
        #expect(calls.withLock { $0 } == 2)
    }
    @Test func webTransportDoesNotRepeatAmbiguousWritesAndReadsCanFallback() async throws {
        let paths = Mutex<[String]>([])
        LibraryStub.handler = { request in
            paths.withLock { $0.append(request.url!.path) }
            if request.url!.path.hasPrefix("/weapi/") { return .init(body: "") }
            return .init(body: #"{"code":200,"data":{"list":[]}}"#)
        }
        let api = api()
        #expect(try await api.recentSongs().isEmpty)
        do { try await api.setAlbumSubscribed(7, subscribed: true); Issue.record("Expected empty response") }
        catch { #expect(error is NeteaseError) }
        #expect(paths.withLock { $0 } == ["/weapi/play-record/song/list", "/eapi/play-record/song/list", "/weapi/album/sub"])
    }
    @Test func webRequestEncodesFormAndScopesCookies() throws {
        let request = try api().client.makeWebRequest("/api/album/sub", data: ["id": 7], authenticated: true)
        #expect(request.url?.host == "music.163.com")
        #expect(request.value(forHTTPHeaderField: "Cookie")?.contains("must-not-send") == false)
        #expect(request.value(forHTTPHeaderField: "Cookie")?.contains("MUSIC_U=test-account") == true)
        let fields = String(decoding: request.httpBody!, as: UTF8.self).split(separator: "&")
        #expect(fields.count == 2)
        #expect(fields[1].dropFirst("encSecKey=".count).count == 256)
        #expect(!fields[0].contains("+"))
    }
    @Test func likedSongsLoadInBoundedPagesAndKeepOrder() async throws {
        let ids = Array(1...102)
        LibraryStub.handler = { request in
            if request.url?.path == "/eapi/song/like/get" {
                return .init(body: "{\"code\":200,\"ids\":\(ids)}")
            }
            let body = try decodeEAPI(request)
            let entries = try JSONSerialization.jsonObject(with: Data((body["c"] as! String).utf8)) as! [[String: Int]]
            #expect(entries.count <= 100)
            let songs = entries.reversed().map { ["id": $0["id"]!, "name": "Song"] as [String: Any] }
            return .init(body: String(decoding: try JSONSerialization.data(withJSONObject: ["code": 200, "songs": songs]), as: UTF8.self))
        }
        let api = api(), library = NeteaseLibrary(api: api), model = NeteasePageModel()
        library.reset(userID: 1)
        await model.load(api: api, route: .liked, userID: 1, library: library)
        #expect(model.songs.map(\.id) == Array(1...100)); #expect(model.more)
        await model.load(api: api, route: .liked, userID: 1, append: true, library: library)
        #expect(model.songs.map(\.id) == ids); #expect(!model.more)
    }
    @Test func albumSubscriptionUsesServerStatusAndUpdatesOnlyAlbumRevision() async throws {
        let paths = Mutex<[String]>([])
        LibraryStub.handler = { request in
            paths.withLock { $0.append(request.url!.path) }
            if request.url!.path.hasSuffix("/dynamic") { return .init(body: #"{"code":200,"isSub":true}"#) }
            return .init(body: #"{"code":200}"#)
        }
        let library = NeteaseLibrary(api: api()); library.reset(userID: 1)
        let album = NeteaseAlbum(id: 7, name: "Album", picUrl: nil, artist: nil)
        try await library.toggleAlbum(album)
        #expect(library.albumStates[7] == false)
        #expect(library.contentRevision(for: .subscribedAlbums) == 1)
        #expect(library.contentRevision(for: .liked) == 0)
        #expect(paths.withLock { $0 } == ["/weapi/album/detail/dynamic", "/weapi/album/unsub"])
    }
    @Test func loggedOutWritesDoNotReachNetwork() async {
        LibraryStub.handler = { _ in Issue.record("Anonymous write reached network"); return .init(body: #"{"code":200}"#) }
        let library = NeteaseLibrary(api: api())
        do { try await library.toggleLike(42); Issue.record("Expected login error") } catch { }
        #expect(library.likedIDs.isEmpty)
    }
    @Test func qualityPaginationUsesCursorAndDeduplicatesOverlappingItems() async throws {
        let calls = Mutex(0)
        LibraryStub.handler = { request in
            let body = try decodeEAPI(request), n = calls.withLock { $0 += 1; return $0 }
            #expect(request.url?.path == "/eapi/playlist/highquality/list")
            #expect(body["lasttime"] as? Int == (n == 1 ? 0 : 500))
            return .init(body: n == 1
                ? #"{"code":200,"playlists":[{"id":1,"name":"One"}],"more":true,"lasttime":500}"#
                : #"{"code":200,"playlists":[{"id":1,"name":"One"},{"id":2,"name":"Two"}],"more":false,"lasttime":400}"#)
        }
        let model = NeteasePageModel(), api = api()
        await model.load(api: api, route: .quality)
        #expect(model.more && model.cursor == 500)
        await model.load(api: api, route: .quality, append: true)
        #expect(model.playlists.map(\.id) == [1, 2]); #expect(!model.more)
    }
    @Test func mutationDuringLikedPageReadReloadsWithNewIDs() async throws {
        let detailCalls = Mutex(0)
        LibraryStub.handler = { request in
            if request.url!.path.hasSuffix("/like/get") { return .init(body: #"{"code":200,"ids":[1]}"#) }
            if request.url!.path.hasSuffix("/radio/like") { return .init(body: #"{"code":200}"#) }
            let n = detailCalls.withLock { $0 += 1; return $0 }
            return .init(body: n == 1
                ? #"{"code":200,"songs":[{"id":1,"name":"One"}]}"#
                : #"{"code":200,"songs":[{"id":1,"name":"One"},{"id":42,"name":"New"}]}"#, delay: n == 1 ? 0.12 : 0)
        }
        let api = api(), library = NeteaseLibrary(api: api), model = NeteasePageModel()
        library.reset(userID: 1); try await library.loadLikes()
        let read = Task { await model.load(api: api, route: .liked, userID: 1, library: library) }
        try await waitFor { detailCalls.withLock { $0 } == 1 }
        try await library.toggleLike(42); await read.value
        #expect(model.songs.map(\.id) == [42, 1])
        #expect(model.libraryRevision == library.contentRevision(for: .liked))
    }

    @Test func homepageMapsSupportedResourcesAndIgnoresUnsupportedContent() throws {
        let json = #"{"blocks":[{"blockCode":"MIXED","uiElement":{"subTitle":{"title":"为你精选"}},"creatives":[{"resources":[{"resourceType":"list","resourceId":7,"uiElement":{"mainTitle":{"title":"List"}}},{"resourceType":"list","resourceId":"7"},{"resourceType":"playlist","resourceId":"7"},{"resourceType":"song","resourceId":"42","resourceExtInfo":{"songData":{"id":42,"name":"Song","ar":[]}}},{"resourceType":"video","resourceId":"8"}]}]}]}"#
        let feed = try JSONDecoder().decode(NeteaseHomeFeed.self, from: Data(json.utf8))
        #expect(feed.blocks[0].title == "为你精选")
        #expect(feed.blocks[0].playlists.map(\.id) == [7])
        #expect(feed.blocks[0].songs.map(\.id) == [42])
    }
    @Test func qualityFallbackUsesImmersiveParameterAndPreservesTrial() async throws {
        let calls = Mutex<[String]>([])
        LibraryStub.handler = { request in
            let body = try decodeEAPI(request)
            let level = try #require(body["level"] as? String)
            calls.withLock { $0.append(level) }
            if level == "sky" { #expect(body["immerseType"] as? String == "c51") }
            else { #expect(body["immerseType"] == nil) }
            return .init(body: level == "lossless"
                ? #"{"code":200,"data":[{"id":42,"url":"http://example.com/song.flac","expi":900,"freeTrialInfo":{"start":0,"end":30}}]}"#
                : #"{"code":200,"data":[{"id":42,"url":null}]}"#)
        }
        let api = api()
        let defaults = try #require(UserDefaults(suiteName: "quality.\(UUID())"))
        let settings = NeteasePlaybackSettings(defaults: defaults, monitorsNetwork: false)
        settings.wifi = .immersive
        let source = try await NeteaseAPI(client: api.client, playbackSettings: settings).stream("42")
        #expect(calls.withLock { $0 } == ["sky", "jyeffect", "lossless"])
        #expect(source.url.scheme == "https" && source.isPreview)
    }

    @Test func qualityDoesNotRetryNetworkOrServerErrors() async throws {
        let calls = Mutex(0)
        LibraryStub.handler = { _ in calls.withLock { $0 += 1 }; return .init(body: #"{"code":405}"#) }
        do { _ = try await api().stream("42"); Issue.record("Expected rejection") } catch { }
        #expect(calls.withLock { $0 } == 1)
    }

    @Test func heartModePreservesRecommendationOrderAndParameters() async throws {
        LibraryStub.handler = { request in
            let body = try decodeEAPI(request)
            if request.url?.path == "/eapi/playmode/intelligence/list" {
                #expect(body["songId"] as? Int == 42)
                #expect(body["startMusicId"] as? Int == 42)
                #expect(body["playlistId"] as? Int == 7)
                #expect(body["type"] as? String == "fromPlayOne")
                return .init(body: #"{"code":200,"data":[{"id":3},{"id":2}]}"#)
            }
            return .init(body: #"{"code":200,"songs":[{"id":2,"name":"Second"},{"id":3,"name":"First"}]}"#)
        }
        #expect(try await api().intelligenceSongs(seedID: 42, playlistID: 7).map(\.id) == [3, 2])
    }

    @Test func emptyHeartModeLeavesPlaybackToCaller() async throws {
        LibraryStub.handler = { _ in .init(body: #"{"code":200,"data":[]}"#) }
        await #expect(throws: NeteasePlaybackError.self) { try await api().intelligenceSongs(seedID: 42, playlistID: 7) }
    }

    @Test func reportingUsesClientLogOSXAndSerialEvents() async throws {
        let events = Mutex<[String]>([])
        LibraryStub.handler = { request in
            #expect(request.url?.host == "clientlog.music.163.com")
            #expect(request.url?.path == "/eapi/feedback/weblog")
            let body = try decodeEAPI(request)
            #expect((body["header"] as? [String: String])?["os"] == "osx")
            let text = try #require(body["logs"] as? String)
            let logs = try #require(JSONSerialization.jsonObject(with: Data(text.utf8)) as? [[String: Any]])
            let event = try #require(logs.first)
            let action = try #require(event["action"] as? String)
            let fields = try #require(event["json"] as? [String: Any])
            #expect(fields["id"] as? String == "42")
            #expect(fields["content"] as? String == "id=7")
            if action == "play" { #expect(fields["time"] as? String == "23") }
            events.withLock { $0.append(action) }
            return .init(body: #"{"code":200}"#, delay: 0.02)
        }
        let reporter = NeteasePlaybackReporter(api: api())
        let track = Track(discID: "9", number: "1", title: "Song", artists: "", albumTitle: "", coverURL: nil,
                          remoteSource: .init(providerID: "netease", itemID: "42"))
        reporter.started(track, sourceID: 7)
        reporter.finished(track, sourceID: 7, seconds: 23.8)
        await reporter.waitForPendingReports()
        #expect(events.withLock { $0 } == ["startplay", "play"])
    }

    @Test func reportingRejectsOldAccountsAndNonNeteaseTracks() async throws {
        LibraryStub.handler = { _ in Issue.record("Unexpected report"); return .init(body: #"{"code":200}"#) }
        let api = api()
        let reporter = NeteasePlaybackReporter(api: api)
        let local = Track(discID: "9", number: "1", title: "Song", artists: "", albumTitle: "", coverURL: nil)
        reporter.started(local, sourceID: nil)
        reporter.finished(local, sourceID: nil, seconds: 10)
        var remote = local; remote.remoteSource = .init(providerID: "netease", itemID: "42")
        reporter.started(remote, sourceID: nil)
        api.client.cookie = "MUSIC_U=another-account"
        reporter.finished(remote, sourceID: nil, seconds: 10)
        await reporter.waitForPendingReports()
        reporter.started(remote, sourceID: nil)
        reporter.reset()
        await reporter.waitForPendingReports()
    }

}

nonisolated private func decodeEAPI(_ request: URLRequest) throws -> [String: Any] {
    var body = request.httpBody
    if body == nil, let stream = request.httpBodyStream {
        stream.open(); defer { stream.close() }
        var buffer = [UInt8](repeating: 0, count: 4096), data = Data()
        while stream.hasBytesAvailable { let n = stream.read(&buffer, maxLength: buffer.count); if n <= 0 { break }; data.append(contentsOf: buffer.prefix(n)) }
        body = data
    }
    let hex = String(decoding: try #require(body), as: UTF8.self).dropFirst(7)
    var encrypted = Data(), index = hex.startIndex
    while index < hex.endIndex { let end = hex.index(index, offsetBy: 2); encrypted.append(try #require(UInt8(hex[index..<end], radix: 16))); index = end }
    var output = Data(count: encrypted.count + 16), length = 0
    let capacity = output.count
    let status = output.withUnsafeMutableBytes { dest in encrypted.withUnsafeBytes { src in
        "e82ckenh8dichen8".withCString { key in
            CCCrypt(CCOperation(kCCDecrypt), CCAlgorithm(kCCAlgorithmAES), CCOptions(kCCOptionECBMode | kCCOptionPKCS7Padding), key, 16, nil, src.baseAddress, encrypted.count, dest.baseAddress, capacity, &length)
        }
    } }
    #expect(status == kCCSuccess)
    let parts = String(decoding: output.prefix(length), as: UTF8.self).components(separatedBy: "-36cd479b6b5-")
    return try #require(JSONSerialization.jsonObject(with: Data(parts[1].utf8)) as? [String: Any])
}
nonisolated private final class LibraryStub: URLProtocol, @unchecked Sendable {
    struct Reply { let body: String; var delay: TimeInterval = 0; var statusCode: Int = 200 }
    nonisolated(unsafe) static var handler: (@Sendable (URLRequest) throws -> Reply)?
    private let stopped = Mutex(false)
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        do {
            let reply = try Self.handler!(request)
            DispatchQueue.global().asyncAfter(deadline: .now() + reply.delay) { [self] in
                guard !stopped.withLock({ $0 }) else { return }
                client?.urlProtocol(self, didReceive: HTTPURLResponse(url: request.url!, statusCode: reply.statusCode, httpVersion: nil, headerFields: nil)!, cacheStoragePolicy: .notAllowed)
                client?.urlProtocol(self, didLoad: Data(reply.body.utf8))
                client?.urlProtocolDidFinishLoading(self)
            }
        } catch { client?.urlProtocol(self, didFailWithError: error) }
    }
    override func stopLoading() { stopped.withLock { $0 = true } }
}
