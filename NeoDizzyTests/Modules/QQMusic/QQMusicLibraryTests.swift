import Foundation
import Synchronization
import Testing
@testable import NeoDizzy

@Suite(.serialized) @MainActor struct QQMusicLibraryTests {
    private func client() -> QQMusicClient {
        let config = URLSessionConfiguration.ephemeral
        config.httpCookieStorage = nil
        config.protocolClasses = [QQMusicLibraryProtocol.self]
        return QQMusicClient(session: URLSession(configuration: config), credential: QQMusicCredential(musicID: "1152921504606846976", musicKey: "synthetic-test-key", loginType: 1))
    }
    private func library() -> QQMusicLibrary {
        let library = QQMusicLibrary(api: client())
        library.reset(accountID: "1152921504606846976")
        return library
    }
    private func configure(includingProfile: Bool = false, _ handler: @escaping @Sendable (URLRequest, [String: Any]) throws -> QQMusicLibraryProtocol.Reply) {
        QQMusicLibraryProtocol.handler.withLock {
            $0 = { request, call in
                if !includingProfile, request.url?.host == "c6.y.qq.com" { return .init(data: ["creator": ["encrypt_uin": "encrypted-account"]], web: true) }
                return try handler(request, call)
            }
        }
    }
    private func waitFor(_ predicate: () -> Bool) async throws {
        for _ in 0..<200 { if predicate() { return }; try await Task.sleep(for: .milliseconds(5)) }
        Issue.record("Request did not start")
    }

    @Test func likedReadPaginatesInOrderUsingEncryptedAccount() async throws {
        configure { _, call in
            #expect(call["method"] as? String == "CgiGetDiss")
            let param = try #require(call["param"] as? [String: Any])
            #expect(param["enc_host_uin"] as? String == "encrypted-account")
            #expect(param["dirid"] as? Int == 201)
            let first = param["song_begin"] as? Int == 0
            return .init(data: ["total_song_num": 3, "hasmore": first ? 1 : 0, "songlist": first ? [Self.song("b", 2), Self.song("a", 1)] : [Self.song("c", 3)]])
        }
        #expect(try await client().likedSongs().map(\.mid) == ["b", "a", "c"])
    }

    @Test func libraryCollectionsSeedDetailArtworkWithoutADetailRequest() async throws {
        configure { _, call in
            switch call["method"] as? String {
            case "GetPlaylistByUin":
                return .init(data: ["v_playlist": [["tid": 123, "dirId": 7, "title": "Saved playlist", "picUrl": "https://example.invalid/saved.jpg"]], "bFinish": true, "total": 1])
            case "CgiGetPlaylistFavInfo":
                return .init(data: ["v_list": [], "hasmore": 0, "total": 0])
            case "CgiGetAlbumFavInfo":
                return .init(data: ["v_list": [["id": 7, "mid": "savedAlbum", "name": "Saved album"]], "hasmore": 0, "total": 1])
            default:
                Issue.record("Unexpected detail request while seeding presentation")
                throw QQMusicError.invalidResponse
            }
        }
        let library = library(), cache = QQMusicContentCache()
        try await library.loadPlaylists()
        try await library.loadAlbums()
        let playlist = cache.page(.playlist("123"), revision: 0, library: library)
        #expect(playlist.title == "Saved playlist" && playlist.artwork == library.playlists.first?.coverURL)
        #expect(!playlist.hasLoaded && playlist.songs.isEmpty)
        let album = cache.page(.album("savedAlbum"), revision: 0, library: library)
        #expect(album.title == "Saved album" && album.artwork == library.albums.first?.coverURL)
        #expect(!album.hasLoaded && album.songs.isEmpty)
    }

    @Test func partialOrRepeatedPagesDoNotReplaceTheSnapshot() async throws {
        configure { _, _ in .init(data: ["total_song_num": 1, "hasmore": 0, "songlist": [Self.song("saved", 1)]]) }
        let library = library()
        try await library.loadLikes()
        configure { _, _ in .init(data: ["total_song_num": 3, "hasmore": 1, "songlist": [Self.song("partial", 2)]]) }
        await #expect(throws: QQMusicError.self) { try await library.loadLikes(force: true) }
        #expect(library.likedSongs.map(\.mid) == ["saved"])
    }

    @Test func libraryReadsUseOfficialProfileThenEncryptedUINAndKeepDirectorySeparate() async throws {
        configure(includingProfile: true) { request, call in
            if request.url?.host == "c6.y.qq.com" {
                #expect(request.httpMethod == "GET")
                let query = Dictionary(uniqueKeysWithValues: (URLComponents(url: request.url!, resolvingAgainstBaseURL: false)?.queryItems ?? []).map { ($0.name, $0.value ?? "") })
                #expect(query["loginUin"] == "1152921504606846976")
                #expect(query["userid"] == "1152921504606846976")
                #expect(query["g_tk"] != nil)
                #expect(request.url?.path == "/rsc/fcgi-bin/fcg_get_profile_homepage.fcg")
                #expect(request.value(forHTTPHeaderField: "Cookie")?.contains("qqmusic_uin=1152921504606846976") == true)
                return .init(data: ["creator": ["encrypt_uin": "encrypted-account"]], web: true)
            }
            let param = call["param"] as? [String: Any] ?? [:]
            switch call["method"] as? String {
            case "GetPlaylistByUin":
                #expect(param["uin"] as? String == "1152921504606846976")
                return .init(data: ["v_playlist": [["tid": "9007199254740993", "dirId": 7, "dirName": "Created"], ["tid": 123, "dirId": 201, "title": "Liked"]], "bFinish": true, "total": 2])
            case "CgiGetPlaylistFavInfo":
                #expect(param["uin"] as? String == "encrypted-account")
                return .init(data: ["v_list": [["tid": 42, "title": "Saved"]], "hasmore": 0, "total": 1])
            case "CgiGetAlbumFavInfo":
                #expect(param["euin"] as? String == "encrypted-account")
                return .init(data: ["v_list": [["id": 7, "mid": "album-mid", "name": "Album"]], "hasmore": 0, "total": 1])
            default: throw QQMusicError.invalidResponse
            }
        }
        let library = library()
        try await library.loadPlaylists(); try await library.loadAlbums()
        #expect(library.writablePlaylists.map(\.id) == ["9007199254740993"])
        #expect(library.writablePlaylists.first?.directoryID == 7)
        #expect(library.albums.first?.id == "album-mid")
        #expect(library.albums.first?.numericID == 7)
    }

    @Test func songWritesKeepNumericIDAndTypeAndCommitOnlyAfterSuccess() async throws {
        let success = Mutex(false)
        configure { _, call in
            if call["method"] as? String == "get_song_detail_yqq" { return .init(data: ["track_info": Self.song("mid", 42, type: 7)]) }
            #expect(call["module"] as? String == "music.musicasset.PlaylistDetailWrite")
            #expect(call["method"] as? String == "AddSonglist")
            let param = try #require(call["param"] as? [String: Any])
            #expect(param["dirId"] as? Int == 201)
            #expect(param["tid"] as? Int == 0)
            #expect(param["bFmtUtf8"] as? Bool == true)
            let song = try #require((param["v_songInfo"] as? [[String: Any]])?.first)
            #expect(song["songId"] as? Int == 42); #expect(song["songType"] as? Int == 7)
            return .init(data: ["retCode": success.withLock { $0 } ? 0 : 9])
        }
        let library = library()
        await #expect(throws: QQMusicError.self) { try await library.setSongLiked(mid: "mid", true) }
        #expect(library.likedSongs.isEmpty && library.pending.isEmpty)
        success.withLock { $0 = true }
        try await library.setSongLiked(mid: "mid", true)
        #expect(library.likedSongs.map(\.mid) == ["mid"])
        #expect(library.songRevision == 1)
    }

    @Test func staleLikeReadCannotUndoSuccessfulWrite() async throws {
        let reading = Mutex(false)
        configure { _, call in
            switch call["method"] as? String {
            case "CgiGetDiss": reading.withLock { $0 = true }; return .init(data: ["total_song_num": 0, "hasmore": 0, "songlist": []], delay: 0.15)
            case "get_song_detail_yqq": return .init(data: ["track_info": Self.song("new", 42)])
            default: return .init(data: ["retCode": 0])
            }
        }
        let library = library()
        let read = Task { try await library.loadLikes(force: true) }
        try await waitFor { reading.withLock { $0 } }
        try await library.setSongLiked(mid: "new", true)
        do { try await read.value; Issue.record("Old read must not publish") } catch is CancellationError { }
        #expect(library.likedSongs.map(\.mid) == ["new"])
    }

    @Test func postWriteReaderCannotJoinAnOlderSharedRead() async throws {
        let reads = Mutex(0)
        configure { _, call in
            switch call["method"] as? String {
            case "CgiGetDiss":
                let count = reads.withLock { $0 += 1; return $0 }
                return count == 1
                    ? .init(data: ["total_song_num": 0, "hasmore": 0, "songlist": []], delay: 0.2)
                    : .init(data: ["total_song_num": 1, "hasmore": 0, "songlist": [Self.song("new", 42)]])
            case "get_song_detail_yqq": return .init(data: ["track_info": Self.song("new", 42)])
            default: return .init(data: ["retCode": 0])
            }
        }
        let library = library()
        let old = Task { try await library.loadLikes(force: true) }
        try await waitFor { reads.withLock { $0 == 1 } }
        try await library.setSongLiked(mid: "new", true)
        try await library.loadLikes(force: true)
        do { try await old.value; Issue.record("Pre-write read must not publish") } catch is CancellationError { }
        #expect(reads.withLock { $0 } == 2)
        #expect(library.likedSongs.map(\.mid) == ["new"])
    }

    @Test func successfulWriteResponseFromOldAccountCannotPublish() async throws {
        let writing = Mutex(false)
        configure { _, call in
            if call["method"] as? String == "get_song_detail_yqq" { return .init(data: ["track_info": Self.song("new", 42)]) }
            writing.withLock { $0 = true }
            return .init(data: ["retCode": 0], delay: 0.1)
        }
        let library = library()
        let write = Task { try await library.setSongLiked(mid: "new", true) }
        try await waitFor { writing.withLock { $0 } }
        library.reset(accountID: "other")
        do { try await write.value; Issue.record("Old account result must be rejected") } catch is CancellationError { }
        #expect(library.likedSongs.isEmpty && library.pending.isEmpty)
    }

    @Test func authenticatedWriteMustMatchLibraryAccountEvenBeforeStorePublishesChange() async throws {
        let api = client()
        await #expect(throws: CancellationError.self) {
            try await api.setSongLiked(QQMusicSong(json: Self.song("new", 42)), liked: true, accountID: "another-account")
        }
        await #expect(throws: CancellationError.self) { try await api.likedSongs(accountID: "another-account") }
        await #expect(throws: CancellationError.self) { try await api.libraryPlaylists(accountID: "another-account") }
        await #expect(throws: CancellationError.self) { try await api.libraryAlbums(accountID: "another-account") }
    }

    @Test func accountChangeWhileResolvingSongCannotWriteIntoNewAccount() async throws {
        let requests = Mutex<[String]>([])
        configure { _, call in
            let method = call["method"] as? String ?? ""
            requests.withLock { $0.append(method) }
            return .init(data: ["track_info": Self.song("new", 42)], delay: 0.1)
        }
        let library = library()
        let write = Task { try await library.setSongLiked(mid: "new", true) }
        try await waitFor { requests.withLock { !$0.isEmpty } }
        library.reset(accountID: "other")
        do { try await write.value; Issue.record("Old account must be cancelled") } catch is CancellationError { }
        #expect(requests.withLock { $0 } == ["get_song_detail_yqq"])
        #expect(library.likedSongs.isEmpty)
    }

    @Test func collectionWritesUseNumericIDsAndOwnPlaylistDirectory() async throws {
        let writes = Mutex<[String]>([])
        configure { _, call in
            let method = call["method"] as? String ?? ""
            let param = call["param"] as? [String: Any] ?? [:]
            switch method {
            case "GetPlaylistByUin": return .init(data: ["bFinish": true, "total": 1, "v_playlist": [["tid": 700, "dirId": 5, "title": "Mine"]]])
            case "CgiGetPlaylistFavInfo": return .init(data: ["hasmore": 0, "total": 1, "v_list": [["tid": 800, "title": "Saved"]]])
            case "CgiGetAlbumFavInfo": return .init(data: ["hasmore": 0, "total": 1, "v_list": [["id": 900, "mid": "album-mid", "title": "Album"]]])
            case "get_song_detail_yqq": return .init(data: ["track_info": Self.song("song-mid", 42, type: 3)])
            case "AddSonglist":
                writes.withLock { $0.append(method) }
                #expect(param["dirId"] as? Int == 5)
                #expect(param["tid"] as? Int == 700)
                return .init(data: ["retCode": 0])
            case "CancelFavPlaylist":
                writes.withLock { $0.append(method) }
                #expect(param["v_playlistId"] as? [Int] == [800])
                #expect(param["uin"] as? String == "encrypted-account")
                return .init(data: ["result": 0, "v_failedPlaylistId": []])
            case "CancelFavAlbum":
                writes.withLock { $0.append(method) }
                #expect(param["v_albumId"] as? [Int] == [900])
                return .init(data: ["result": 0, "v_failedAlbumId": []])
            default: throw QQMusicError.invalidResponse
            }
        }
        let library = library()
        try await library.loadPlaylists(); try await library.loadAlbums()
        let own = try #require(library.writablePlaylists.first)
        try await library.togglePlaylist(own.collection)
        #expect(writes.withLock { $0 }.isEmpty)
        try await library.addSong(mid: "song-mid", to: own)
        #expect(library.contentRevision(playlistID: "700") == 1)
        try await library.unsubscribePlaylist(id: "800")
        try await library.unsubscribeAlbum(id: "album-mid")
        #expect(library.playlists.map(\.id) == ["700"] && library.albums.isEmpty)
        #expect(writes.withLock { $0 } == ["AddSonglist", "CancelFavPlaylist", "CancelFavAlbum"])
    }

    @Test func failedItemInWriteEnvelopeMustNotReportSuccess() {
        #expect(throws: QQMusicError.self) { try QQMusicClient.checkLibraryWrite(["result": 0, "v_failedAlbumId": [7]], failedKey: "v_failedAlbumId") }
        #expect(throws: QQMusicError.self) { try QQMusicClient.checkLibraryWrite([:], failedKey: "v_failedAlbumId") }
        #expect(throws: QQMusicError.self) { try QQMusicClient.checkLibraryListReadable(["hide": true], failedKey: "v_failTids") }
    }

    @Test func mirrorPreservesOtherProvidersAndOwnedCollections() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let mirror = AccountLibraryMirror(directory: directory)
        mirror.register("netease", account: { "other" }, refresh: { _ in })
        mirror.replace("netease", collections: [mirror.item(providerID: "netease", kind: .album, itemID: "7", title: "Other", subtitle: "", coverURL: nil)])
        let store = QQMusicStore(credential: .init(musicID: "account", musicKey: "test"), restoreSaved: false, saveCredential: { _ in })
        mirror.registerQQMusic(store)
        mirror.rebuildQQMusic(from: store)
        #expect(mirror.collections.map(\.providerID) == ["netease"])
        store.deactivate()
        #expect(mirror.collections.map(\.providerID) == ["netease"])
    }

    nonisolated private static func song(_ mid: String, _ id: Int, type: Int = 0) -> [String: Any] {
        ["id": id, "mid": mid, "title": mid, "type": type]
    }
}

nonisolated private final class QQMusicLibraryProtocol: URLProtocol, @unchecked Sendable {
    struct Reply: @unchecked Sendable {
        let data: [String: Any]
        var delay: TimeInterval = 0
        var web = false
    }
    static let handler = Mutex<(@Sendable (URLRequest, [String: Any]) throws -> Reply)?>(nil)
    private let work = Mutex<DispatchWorkItem?>(nil)
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        do {
            var bytes = request.httpBody ?? Data()
            if bytes.isEmpty, let stream = request.httpBodyStream {
                stream.open(); defer { stream.close() }
                var buffer = [UInt8](repeating: 0, count: 4096)
                while stream.hasBytesAvailable {
                    let count = stream.read(&buffer, maxLength: buffer.count)
                    if count < 0 { throw URLError(.cannotDecodeRawData) }
                    if count == 0 { break }
                    bytes.append(contentsOf: buffer.prefix(count))
                }
            }
            let root: [String: Any]
            if bytes.isEmpty { root = [:] }
            else { root = try JSONSerialization.jsonObject(with: bytes) as? [String: Any] ?? [:] }
            let call = root["req_0"] as? [String: Any] ?? [:]
            guard let handler = Self.handler.withLock({ $0 }) else { throw URLError(.badServerResponse) }
            let reply = try handler(request, call)
            let object: [String: Any] = reply.web ? ["code": 0, "data": reply.data] : ["code": 0, "req_0": ["code": 0, "data": reply.data]]
            let body = try JSONSerialization.data(withJSONObject: object)
            let item = DispatchWorkItem { [weak self] in
                guard let self else { return }
                self.client?.urlProtocol(self, didReceive: HTTPURLResponse(url: self.request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!, cacheStoragePolicy: .notAllowed)
                self.client?.urlProtocol(self, didLoad: body)
                self.client?.urlProtocolDidFinishLoading(self)
            }
            work.withLock { $0 = item }
            DispatchQueue.global().asyncAfter(deadline: .now() + reply.delay, execute: item)
        } catch { client?.urlProtocol(self, didFailWithError: error) }
    }
    override func stopLoading() { work.withLock { $0?.cancel(); $0 = nil } }
}
