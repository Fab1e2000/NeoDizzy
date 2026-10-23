import Foundation
import Testing
@testable import NeoDizzy

struct QQMusicAPITests {
    @Test func mapsProviderIdentityAndAlbumCover() throws {
        let song = try QQMusicSong(json: ["id": 97773, "mid": "0039MnYb0qxYhV", "title": "晴天", "singer": [["name": "周杰伦"]], "album": ["mid": "000MkMni19ClKG", "title": "叶惠美"], "interval": 269])
        #expect(song.id == "97773")
        #expect(song.track.id == "remote/qqmusic/0039MnYb0qxYhV")
        #expect(song.track.discID == "000MkMni19ClKG")
        #expect(song.artist == "周杰伦")
        #expect(song.duration == 269)
        #expect(song.coverURL?.scheme == "https")
    }

    @Test func malformedSongDoesNotEnterQueue() {
        #expect(throws: QQMusicError.self) { try QQMusicSong(json: ["title": "No MID"]) }
    }

    @Test func emptyVkeyNeverBecomesPreviewOrFakeAudio() {
        #expect(throws: QQMusicError.self) {
            try QQMusicClient.playbackSource(["midurlinfo": [["songmid": "mid", "purl": ""]]], mid: "mid")
        }
    }

    @Test func streamSelectsMatchingSongAndHTTPS() throws {
        let source = try QQMusicClient.playbackSource([
            "sip": ["http://legacy.example/", "https://audio.example/"],
            "midurlinfo": [["songmid": "other", "purl": "other.mp3"], ["songmid": "mid", "purl": "M500midmid.mp3?vkey=test"]]
        ], mid: "mid")
        #expect(source.url.host == "audio.example")
        #expect(source.url.path == "/M500midmid.mp3")
        #expect(!source.isPreview)
        #expect(source.actualQuality == "mp3_128")
    }

    @Test func missingSongSectionIsAnEmptySearchResult() throws {
        #expect(try QQMusicClient.searchSongs(["body": ["item_album": ["items": []]]]).isEmpty)
        #expect(try QQMusicClient.searchSongs(["body": ["item_song": [:]]]).isEmpty)
        #expect(throws: QQMusicError.self) { try QQMusicClient.searchSongs(["body": "invalid"]) }
        #expect(throws: QQMusicError.self) { try QQMusicClient.searchSongs(["body": ["item_song": "invalid"]]) }
    }

    @Test func previewAndUnknownFormatsCannotEnterFullTrackCache() {
        for path in ["RS02mid.mp3?vkey=test", "O802mid.ogg?vkey=test", "unknown.mp3", "M500mid.ogg"] {
            #expect(throws: QQMusicError.self) {
                try QQMusicClient.playbackSource(["midurlinfo": [["songmid": "mid", "purl": path]]], mid: "mid")
            }
        }
    }

    @Test func disabledClientRejectsNetworkWork() async {
        let client = QQMusicClient()
        await client.setEnabled(false)
        await #expect(throws: QQMusicError.self) { try await client.search(query: "test") }
    }

    @Test func credentialRoundTripKeepsLoginType() throws {
        let credential = QQMusicCredential(musicID: "123", musicKey: "test", loginType: 2, nickname: "测试")
        let restored = try JSONDecoder().decode(QQMusicCredential.self, from: JSONEncoder().encode(credential))
        #expect(restored == credential)
    }
}

nonisolated final class QQMusicRequestEchoProtocol: URLProtocol, @unchecked Sendable {
    nonisolated override class func canInit(with request: URLRequest) -> Bool { true }
    nonisolated override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    nonisolated override func startLoading() {
        let cookie = request.value(forHTTPHeaderField: "Cookie") ?? "guest"
        let object: [String: Any] = ["code": 0, "req_0": ["code": 0, "data": ["body": ["item_song": ["items": [["id": 1, "mid": "test", "title": cookie]]]]]]]
        let bytes = try! JSONSerialization.data(withJSONObject: object)
        client?.urlProtocol(self, didReceive: HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: bytes)
        client?.urlProtocolDidFinishLoading(self)
    }
    nonisolated override func stopLoading() {}
}

extension QQMusicAPITests {
    @Test func uncommittedCredentialCanBeRestoredAfterNetworkInvalidation() async throws {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [QQMusicRequestEchoProtocol.self]
        configuration.httpCookieStorage = nil
        let original = QQMusicCredential(musicID: "123", musicKey: "original-key")
        let client = QQMusicClient(session: URLSession(configuration: configuration), credential: original)
        let token = await client.setCredential(QQMusicCredential(musicID: "456", musicKey: "uncommitted-key"))

        await client.setEnabled(false)
        await client.restoreCredential(original, ifCurrent: token)
        await client.setEnabled(true)

        #expect(try await client.search(query: "test").first?.title.contains("original-key") == true)
    }

    @Test func rollbackCannotReplaceANewerCredentialOrLogout() async throws {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [QQMusicRequestEchoProtocol.self]
        configuration.httpCookieStorage = nil
        let original = QQMusicCredential(musicID: "123", musicKey: "original-key")
        let newer = QQMusicCredential(musicID: "789", musicKey: "newer-key")
        let client = QQMusicClient(session: URLSession(configuration: configuration), credential: original)
        let replacements: [QQMusicCredential?] = [newer, nil]
        for replacement in replacements {
            let token = await client.setCredential(QQMusicCredential(musicID: "456", musicKey: "uncommitted-key"))
            await client.setCredential(replacement)
            await client.restoreCredential(original, ifCurrent: token)

            let cookie = try #require(await client.search(query: "test").first?.title)
            #expect(replacement == nil ? cookie == "guest" : cookie.contains("newer-key"))
        }
    }

    @Test func credentialsAreScopedToClientAndClearedOnLogout() async throws {
        func session() -> URLSession {
            let configuration = URLSessionConfiguration.ephemeral
            configuration.protocolClasses = [QQMusicRequestEchoProtocol.self]
            configuration.httpCookieStorage = nil
            return URLSession(configuration: configuration)
        }
        let signedIn = QQMusicClient(session: session(), credential: QQMusicCredential(musicID: "123", musicKey: "isolated-key"))
        let guest = QQMusicClient(session: session())
        let signedInResult = try await signedIn.search(query: "test")
        #expect(signedInResult.first?.title.contains("isolated-key") == true)
        #expect(try await guest.search(query: "test").first?.title == "guest")
        await signedIn.setCredential(nil)
        #expect(try await signedIn.search(query: "test").first?.title == "guest")
    }
}

extension QQMusicAPITests {
    @Test func chartGroupsPreserveServerOrderAndFilterUnsupportedDestinations() throws {
        let groups = try QQMusicClient.chartGroups(data: ["group": [
            ["groupId": 2, "groupName": "特色榜", "toplist": [
                ["topId": 50, "title": "A", "frontPicUrl": "http://example.com/a.jpg"],
                ["topId": 50, "title": "重复"],
                ["topId": 201, "title": "MV", "h5JumpUrl": "https://example.com"],
                ["topId": 202, "title": "客户端", "specialScheme": "qqmusic://x"]
            ]],
            ["groupId": 0, "groupName": "巅峰榜", "toplist": [["topId": 50, "title": "跨组重复"], ["topId": 62, "title": "B"]]],
            ["groupId": 2, "groupName": "重复组", "toplist": [["topId": 99, "title": "C"]]],
            ["groupId": 4, "groupName": "空组", "toplist": []]
        ]])
        #expect(groups.map(\.id) == ["2", "0"])
        #expect(groups.map(\.title) == ["特色榜", "巅峰榜"])
        #expect(groups.flatMap(\.charts).map(\.id) == ["50", "62"])
        #expect(groups.first?.charts.first?.coverURL?.scheme == "https")
    }

    @Test func chartGroupsRejectMalformedGroupsAndAcceptEmptyResponse() throws {
        #expect(try QQMusicClient.chartGroups(data: ["group": []]).isEmpty)
        #expect(throws: QQMusicError.self) { try QQMusicClient.chartGroups(data: [:]) }
        #expect(throws: QQMusicError.self) {
            try QQMusicClient.chartGroups(data: ["group": [["groupId": 0, "groupName": "榜单", "toplist": "wrong"]]])
        }
    }

    @Test func recommendedPlaylistIDsAndCursorAreNotDerivedFromItemCount() throws {
        let item: [String: Any] = ["Playlist": ["basic": ["tid": "009007199254740993", "title": "推荐", "cover": ["default_url": "https://example.com/cover.jpg"]]]]
        let page = try QQMusicClient.recommendedPlaylistPage(data: ["List": [item, item], "HasMore": true, "FromLimit": 400], cursor: 0)
        #expect(page.items.map(\.id) == ["009007199254740993"])
        #expect(page.items.first?.title == "推荐")
        #expect(page.nextCursor == 400)
        #expect(try QQMusicClient.recommendedPlaylistPage(data: ["List": [], "HasMore": true, "FromLimit": 400], cursor: 400).nextCursor == nil)
        #expect(try QQMusicClient.recommendedPlaylistPage(data: ["List": [], "HasMore": true, "FromLimit": 300], cursor: 400).nextCursor == nil)
        #expect(try QQMusicClient.recommendedPlaylistPage(data: ["List": [], "HasMore": false, "FromLimit": 800], cursor: 400).nextCursor == nil)
    }

    @Test func recommendedPlaylistPageRejectsMalformedDataButAcceptsEmptyList() throws {
        #expect(try QQMusicClient.recommendedPlaylistPage(data: ["List": [], "HasMore": false, "FromLimit": 0], cursor: 0).items.isEmpty)
        let malformed: [[String: Any]] = [[:], ["List": "wrong", "HasMore": false, "FromLimit": 0], ["List": [["Playlist": [:]]], "HasMore": false, "FromLimit": 0]]
        for data in malformed {
            #expect(throws: QQMusicError.self) { try QQMusicClient.recommendedPlaylistPage(data: data, cursor: 0) }
        }
    }

    @Test func recommendedPlaylistRequestUsesReturnedCursorAndRequestedSize() async throws {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [QQMusicPlaylistRequestProtocol.self]
        let client = QQMusicClient(session: URLSession(configuration: configuration))
        let first = try await client.recommendedPlaylists()
        #expect(first.items.first?.title == "music.playlist.PlaylistSquare/GetRecommendFeed/0/30")
        let cursor = try #require(first.nextCursor)
        #expect(cursor == 400)
        let second = try await client.recommendedPlaylists(cursor: cursor, limit: 8)
        #expect(second.items.first?.title == "music.playlist.PlaylistSquare/GetRecommendFeed/400/8")
        #expect(second.nextCursor == 800)
    }
}

nonisolated private final class QQMusicPlaylistRequestProtocol: URLProtocol, @unchecked Sendable {
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        do {
            var body = request.httpBody ?? Data()
            if body.isEmpty, let stream = request.httpBodyStream {
                stream.open()
                defer { stream.close() }
                var buffer = [UInt8](repeating: 0, count: 4096)
                while stream.hasBytesAvailable {
                    let count = stream.read(&buffer, maxLength: buffer.count)
                    if count < 0 { throw URLError(.cannotDecodeRawData) }
                    if count == 0 { break }
                    body.append(contentsOf: buffer.prefix(count))
                }
            }
            guard let root = try JSONSerialization.jsonObject(with: body) as? [String: Any],
                  let call = root["req_0"] as? [String: Any], let param = call["param"] as? [String: Any],
                  let cursor = param["From"] as? Int, let size = param["Size"] as? Int,
                  let module = call["module"] as? String, let method = call["method"] as? String else { throw URLError(.badServerResponse) }
            let title = "\(module)/\(method)/\(cursor)/\(size)"
            let data: [String: Any] = ["List": [["Playlist": ["basic": ["tid": 7468450811, "title": title, "cover": ["default_url": "https://example.com/a.jpg"]]]]], "HasMore": true, "FromLimit": cursor + 400]
            let bytes = try JSONSerialization.data(withJSONObject: ["code": 0, "req_0": ["code": 0, "data": data]])
            client?.urlProtocol(self, didReceive: HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: bytes)
            client?.urlProtocolDidFinishLoading(self)
        } catch { client?.urlProtocol(self, didFailWithError: error) }
    }
    override func stopLoading() {}
}

extension QQMusicAPITests {
    @Test func radioAndRadarParseRealSongIdentityWithoutInventingDailySemantics() throws {
        let track: [String: Any] = ["id": "9007199254740993", "mid": "radar-mid", "title": "推荐歌曲", "interval": 200]
        let guess = try QQMusicClient.guessSongs(data: ["tracks": [track]])
        #expect(guess.first?.id == "9007199254740993")
        #expect(guess.first?.track.remoteSource?.itemID == "radar-mid")
        let radar = try QQMusicClient.radarSongs(data: ["VecSongs": [["Track": track]], "HasMore": true])
        #expect(radar.items.map(\.mid) == ["radar-mid"])
        #expect(radar.hasMore)
        #expect(try QQMusicClient.guessSongs(data: ["tracks": []]).isEmpty)
        let empty = try QQMusicClient.radarSongs(data: ["VecSongs": [], "HasMore": false])
        #expect(empty.items.isEmpty)
        #expect(!empty.hasMore)
    }

    @Test func radioAndRadarRejectMalformedResponses() {
        #expect(throws: QQMusicError.self) { try QQMusicClient.guessSongs(data: [:]) }
        #expect(throws: QQMusicError.self) { try QQMusicClient.guessSongs(data: ["tracks": [["title": "No MID"]]]) }
        #expect(throws: QQMusicError.self) { try QQMusicClient.radarSongs(data: ["VecSongs": [], "HasMore": "true"]) }
        #expect(throws: QQMusicError.self) { try QQMusicClient.radarSongs(data: ["VecSongs": [["wrong": [:]]], "HasMore": true]) }
    }

    @Test func webRadioRequiresCredentialBeforeSendingRequest() async throws {
        let credentials: [QQMusicCredential?] = [nil, QQMusicCredential(musicID: "0", musicKey: "test"), QQMusicCredential(musicID: "123", musicKey: "")]
        for credential in credentials {
            let client = QQMusicClient(session: recommendationSession(), credential: credential)
            do {
                _ = try await client.guessSongs()
                Issue.record("Guest radio must require login before making a request")
            } catch QQMusicError.loginRequired {
            }
        }
    }

    @Test func radioRequestUsesUpstreamFiveSongBatchContract() async throws {
        let client = QQMusicClient(session: recommendationSession(), credential: QQMusicCredential(musicID: "123", musicKey: "synthetic-test-key"))
        let track = try #require(await client.guessSongs().first)
        let call = try #require(JSONSerialization.jsonObject(with: Data(track.title.utf8)) as? [String: Any])
        #expect(call["module"] as? String == "music.radioProxy.MbTrackRadioSvr")
        #expect(call["method"] as? String == "get_radio_track")
        let param = try #require(call["param"] as? [String: Any])
        #expect(param["id"] as? Int == 99)
        #expect(param["num"] as? Int == 5)
        #expect(param["from"] as? Int == 0)
        #expect(param["scene"] as? Int == 0)
        #expect((param["song_ids"] as? [Int])?.isEmpty == true)
    }

    @Test func radarRequestUsesRequestedPageAndServerHasMore() async throws {
        let client = QQMusicClient(session: recommendationSession())
        let result = try await client.radarSongs(page: 7)
        let track = try #require(result.items.first)
        let call = try #require(JSONSerialization.jsonObject(with: Data(track.title.utf8)) as? [String: Any])
        #expect(call["module"] as? String == "music.recommend.TrackRelationServer")
        #expect(call["method"] as? String == "GetRadarSong")
        let param = try #require(call["param"] as? [String: Any])
        #expect(param["Page"] as? Int == 7)
        #expect(param["ReqType"] as? Int == 0)
        #expect((param["FavSongs"] as? [Int])?.isEmpty == true)
        #expect((param["EntranceSongs"] as? [Int])?.isEmpty == true)
        #expect(result.hasMore == false)
        await #expect(throws: QQMusicError.self) { try await client.radarSongs(page: 0) }
    }

    private func recommendationSession() -> URLSession {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [QQMusicRecommendationProtocol.self]
        configuration.httpCookieStorage = nil
        return URLSession(configuration: configuration)
    }
}

nonisolated private final class QQMusicRecommendationProtocol: URLProtocol, @unchecked Sendable {
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        do {
            var body = request.httpBody ?? Data()
            if body.isEmpty, let stream = request.httpBodyStream {
                stream.open()
                defer { stream.close() }
                var buffer = [UInt8](repeating: 0, count: 4096)
                while stream.hasBytesAvailable {
                    let count = stream.read(&buffer, maxLength: buffer.count)
                    if count < 0 { throw URLError(.cannotDecodeRawData) }
                    if count == 0 { break }
                    body.append(contentsOf: buffer.prefix(count))
                }
            }
            guard let root = try JSONSerialization.jsonObject(with: body) as? [String: Any],
                  let call = root["req_0"] as? [String: Any], let method = call["method"] as? String else { throw URLError(.badServerResponse) }
            let title = String(decoding: try JSONSerialization.data(withJSONObject: call), as: UTF8.self)
            let track: [String: Any] = ["id": 1333803, "mid": "001hUNRP0P8g7x", "title": title]
            let data: [String: Any]
            switch method {
            case "GetRadarSong": data = ["VecSongs": [["Track": track]], "HasMore": false]
            case "CgiGetDiss": data = ["songlist": [["songInfo": track]]]
            default: data = ["tracks": [track]]
            }
            let bytes = try JSONSerialization.data(withJSONObject: ["code": 0, "req_0": ["code": 0, "data": data]])
            client?.urlProtocol(self, didReceive: HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: bytes)
            client?.urlProtocolDidFinishLoading(self)
        } catch { client?.urlProtocol(self, didFailWithError: error) }
    }
    override func stopLoading() {}
}


extension QQMusicAPITests {
    @Test func dailySongsParseKnownWrappersAndDirectRowsInOrder() throws {
        let song: [String: Any] = ["id": "9007199254740993", "mid": "daily-mid", "title": "每日歌曲"]
        let result = try QQMusicClient.dailySongs(data: ["songlist": [["songInfo": song], ["songinfo": song], song]])
        #expect(result.count == 3)
        #expect(result.allSatisfy { $0.id == "9007199254740993" && $0.mid == "daily-mid" })
        #expect(try QQMusicClient.dailySongs(data: ["songlist": []]).isEmpty)
    }

    @Test func dailySongsRejectMalformedRowsInsteadOfSilentlyDroppingThem() {
        let malformed: [[String: Any]] = [[:], ["songlist": "wrong"], ["songlist": [["songInfo": "wrong", "mid": "would-hide-error", "title": "x"]]], ["songlist": [["songinfo": NSNull()]]], ["songlist": [["title": "Missing MID"]]]]
        for response in malformed {
            #expect(throws: QQMusicError.self) { try QQMusicClient.dailySongs(data: response) }
        }
    }

    @Test func dailyRequestMatchesVerifiedFourFieldContract() async throws {
        let client = QQMusicClient(session: recommendationSession(), credential: QQMusicCredential(musicID: "123", musicKey: "synthetic-test-key"))
        let before = Int(Date().timeIntervalSince1970)
        let track = try #require(await client.dailySongs().first)
        let after = Int(Date().timeIntervalSince1970)
        let call = try #require(JSONSerialization.jsonObject(with: Data(track.title.utf8)) as? [String: Any])
        #expect(call["module"] as? String == "music.srfDissInfo.DissInfo")
        #expect(call["method"] as? String == "CgiGetDiss")
        let param = try #require(call["param"] as? [String: Any])
        #expect(Set(param.keys) == ["dirid", "uinAttached", "enc_host_uin", "local_time"])
        #expect(param["dirid"] as? Int == 202)
        #expect(param["uinAttached"] as? Bool == true)
        #expect(param["enc_host_uin"] as? String == "123")
        let timestamp = try #require(param["local_time"] as? Int)
        #expect((before...after).contains(timestamp))
    }

    @Test func dailyRequiresLoginAndRespectsModuleDisable() async throws {
        let credentials: [QQMusicCredential?] = [nil, QQMusicCredential(musicID: "0", musicKey: "test"), QQMusicCredential(musicID: "123", musicKey: "")]
        for credential in credentials {
            let client = QQMusicClient(session: recommendationSession(), credential: credential)
            do {
                _ = try await client.dailySongs()
                Issue.record("Daily recommendations must require login before making a request")
            } catch QQMusicError.loginRequired {}
        }
        let client = QQMusicClient(session: recommendationSession(), credential: QQMusicCredential(musicID: "123", musicKey: "test"))
        await client.setEnabled(false)
        do {
            _ = try await client.dailySongs()
            Issue.record("A disabled module must not load daily recommendations")
        } catch QQMusicError.disabled {}
    }
}
