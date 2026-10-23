import Foundation
import Synchronization
import Testing
@testable import NeoDizzy

@Suite(.serialized) @MainActor
struct QQMusicDownloadTests {
    private func client(_ responses: [[String: Any]]) throws -> QQMusicClient {
        let bytes = try responses.map { try JSONSerialization.data(withJSONObject: ["code": 0, "req_0": ["code": 0, "data": $0]]) }
        QQDownloadProtocol.state.withLock { $0 = (bytes, []) }
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [QQDownloadProtocol.self]
        return QQMusicClient(session: URLSession(configuration: configuration), credential: .init(musicID: "123", musicKey: "synthetic"))
    }
    private func defaults() throws -> UserDefaults { try #require(UserDefaults(suiteName: "QQDownload.\(UUID())")) }
    private func track(_ mid: String = "mid") -> Track {
        Track(discID: "album", number: "1", title: "歌曲", artists: "歌手", albumTitle: "专辑", coverURL: nil,
              remoteSource: .init(providerID: "qqmusic", itemID: mid))
    }
    private func metadata(_ quality: QQMusicQuality = .lossless) -> QQMusicDownloadMetadata {
        QQMusicDownloadMetadata(track: track(), trackNumber: 2, discNumber: 1, quality: quality)
    }
    private func source(_ path: String) -> [String: Any] { ["midurlinfo": [["songmid": "mid", "purl": path]]] }

    @Test func unifiedQualityPersistsAndOnlyChangesNotify() throws {
        let defaults = try defaults(), settings = QQMusicPlaybackSettings(defaults: defaults)
        var changes = 0
        settings.changed = { changes += 1 }
        #expect(settings.quality == .high)
        settings.quality = .lossless
        settings.quality = .lossless
        #expect(changes == 1)
        #expect(QQMusicPlaybackSettings(defaults: defaults).quality == .lossless)
        #expect(QQMusicQuality.master.fallbacks == [.master, .lossless, .high, .standard])
    }

    @Test func qualityFallbackUsesFullNativeFormatsInOrder() async throws {
        let api = try client([source(""), source(""), source("M800midmid.mp3?vkey=synthetic")])
        let resolved = try await api.stream(mid: "mid", quality: .master)
        #expect(resolved.actualQuality == QQMusicQuality.high.rawValue)
        #expect(resolved.fileExtension == "mp3")
        let filenames = try QQDownloadProtocol.state.withLock { $0.1 }.map { data -> String in
            let root = try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
            let call = try #require(root["req_0"] as? [String: Any]), param = try #require(call["param"] as? [String: Any])
            return try #require((param["filename"] as? [String])?.first)
        }
        #expect(filenames == ["AI00midmid.flac", "F000midmid.flac", "M800midmid.mp3"])
    }

    @Test(arguments: QQMusicQuality.allCases)
    func allQualitiesRejectPreviewEncryptedAndWrongFormat(_ quality: QQMusicQuality) throws {
        for path in ["RS02mid.mp3", "O802mid.ogg", "F0M0mid.mflac", "M500mid.flac", "AI00mid.mp3"] {
            #expect(throws: QQMusicError.self) { try QQMusicClient.playbackSource(source(path), mid: "mid", quality: quality) }
        }
        let result = try QQMusicClient.playbackSource(source("\(quality.prefix)midmid.\(quality.fileExtension)"), mid: "mid", quality: quality)
        #expect(result.actualQuality == quality.rawValue)
    }

    @Test func playlistPlanKeepsOrderCoverAndNativeTrackNumbersWithoutCredentials() async throws {
        func song(_ mid: String, number: Int) -> [String: Any] {
            ["mid": mid, "title": mid, "index_album": number, "index_cd": 2, "album": ["mid": "album", "title": "专辑"]]
        }
        let api = try client([["dirinfo": ["title": "歌单", "picurl": "https://example.com/cover.jpg"],
                               "songlist": [song("a", number: 3), song("b", number: 7)], "hasmore": 0, "total_song_num": 2]])
        let provider = QQMusicDownloadProvider(api: api, library: OfflineLibraryStore(defaults: try defaults()), cacheScope: { "synthetic-scope" })
        let request = DownloadRequest(title: "歌单", identity: "playlist/99", coverURL: nil,
            payload: try JSONEncoder().encode(QQMusicDownloadRequest(kind: "playlist", id: "99", quality: .lossless)))
        let planned = try await provider.plan(JSONEncoder().encode(request))
        let metadata = try planned.map { try JSONDecoder().decode(QQMusicDownloadMetadata.self, from: $0.metadata) }
        #expect(metadata.map(\.track.remoteSource?.itemID) == ["a", "b"])
        #expect(metadata.map(\.trackNumber) == [3, 7])
        #expect(metadata.map(\.discNumber) == [2, 2])
        #expect(metadata.map(\.playlistPosition) == [1, 2])
        #expect(metadata.allSatisfy { $0.playlistID == "99" && $0.playlistArtworkURL?.absoluteString == "https://example.com/cover.jpg" })
        let encoded = String(decoding: try JSONEncoder().encode(metadata), as: UTF8.self)
        #expect(!encoded.contains("synthetic-scope"))
        #expect(!encoded.contains("vkey"))
        #expect(provider.summary(for: planned[0])?.title == "a")
    }

    @Test func completePlaybackCacheIsReusedAndRemovedFromOriginalScopeOnly() async throws {
        let scopeA = "qqmusic/test-\(UUID())", scopeB = "qqmusic/test-\(UUID())"
        var scope = scopeA
        let metadata = metadata(), api = try client([])
        let keyA = AudioPlaybackCache.Key(trackID: metadata.track.id, scope: scopeA, quality: metadata.quality.rawValue)
        let keyB = AudioPlaybackCache.Key(trackID: metadata.track.id, scope: scopeB, quality: metadata.quality.rawValue)
        let file = URL.temporaryDirectory.appendingPathComponent("\(UUID()).mp3"), bytes = try Fixture.data("audio-local-tags.mp3")
        try bytes.write(to: file)
        defer { AudioPlaybackCache.shared.remove(keyA); AudioPlaybackCache.shared.remove(keyB); try? FileManager.default.removeItem(at: file) }
        try await AudioPlaybackCache.shared.commit(file, key: keyA, actualQuality: "mp3_320", bytes: Int64(bytes.count), fileExtension: "mp3")
        try await AudioPlaybackCache.shared.commit(file, key: keyB, actualQuality: "mp3_320", bytes: Int64(bytes.count), fileExtension: "mp3")
        let provider = QQMusicDownloadProvider(api: api, library: OfflineLibraryStore(defaults: try defaults()), cacheScope: { scope })
        var transfer = DownloadTransfer(id: UUID(), metadata: try JSONEncoder().encode(metadata))
        let result = try #require(try await provider.source(transfer))
        #expect(result.url.isFileURL)
        #expect(try Data(contentsOf: result.url) == bytes)
        #expect(try JSONDecoder().decode(QQMusicDownloadMetadata.self, from: result.metadata).actualQuality == "mp3_320")
        #expect(QQDownloadProtocol.state.withLock { $0.1.isEmpty })
        scope = scopeB
        transfer.state = .completed
        try await provider.completed(Data(), transfers: [transfer])
        #expect(AudioPlaybackCache.shared.entry(for: keyA) == nil)
        #expect(AudioPlaybackCache.shared.entry(for: keyB) != nil)
    }

    @Test func albumPlanUsesTrackNumbersInsteadOfResponseOrder() async throws {
        func row(_ mid: String, number: Int) -> [String: Any] {
            ["songInfo": ["mid": mid, "title": mid, "index_album": number, "index_cd": 0,
                          "album": ["mid": "album", "title": "专辑"]]]
        }
        let api = try client([["basicInfo": ["title": "专辑"]],
                              ["songList": [row("second", number: 2), row("first", number: 1)], "totalNum": 2]])
        let provider = QQMusicDownloadProvider(api: api, library: OfflineLibraryStore(defaults: try defaults()), cacheScope: { "test" })
        let request = DownloadRequest(title: "专辑", identity: "album/album", coverURL: nil,
            payload: try JSONEncoder().encode(QQMusicDownloadRequest(kind: "album", id: "album", quality: .standard)))
        let planned = try await provider.plan(JSONEncoder().encode(request))
        let metadata = try planned.map { try JSONDecoder().decode(QQMusicDownloadMetadata.self, from: $0.metadata) }
        #expect(metadata.map(\.track.remoteSource?.itemID) == ["first", "second"])
        #expect(metadata.map(\.trackNumber) == [1, 2])
        #expect(metadata.allSatisfy { $0.playlistID == nil && $0.discNumber == 1 })
    }

    @Test func accountChangeBetweenDownloadAndFinalizeRejectsStaleTransfer() async throws {
        var revision = 1
        let provider = QQMusicDownloadProvider(api: try client([source("M500midmid.mp3")]),
            library: OfflineLibraryStore(defaults: try defaults()), cacheScope: { "stable" }, sessionRevision: { revision })
        let transfer = DownloadTransfer(id: UUID(), metadata: try JSONEncoder().encode(metadata(.standard)))
        let source = try #require(try await provider.source(transfer))
        revision = 2
        await #expect(throws: QQMusicDownloadError.self) {
            try await provider.finalize(URL(fileURLWithPath: "/missing"), metadata: source.metadata, staging: .temporaryDirectory)
        }
    }

    @Test(arguments: ["mp3", "flac"])
    func finalizationWritesNativeAudioTagsAndPlaylistManifest(_ type: String) async throws {
        let root = URL.temporaryDirectory.appendingPathComponent(UUID().uuidString), staging = root.appendingPathComponent("staging")
        try FileManager.default.createDirectory(at: staging, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let file = root.appendingPathComponent("download.archive")
        try Fixture.data("audio-local-tags.\(type)").write(to: file)
        let lyrics = "[00:01.00]歌词\n[00:01.00]Translation"
        let provider = QQMusicDownloadProvider(api: try client([["lyric": Data(lyrics.utf8).base64EncodedString()]]),
            library: OfflineLibraryStore(defaults: try defaults()), cacheScope: { "test" })
        var metadata = metadata()
        metadata.type = type; metadata.actualQuality = type == "flac" ? "flac" : "mp3_320"
        metadata.playlistID = "99"; metadata.playlistTitle = "歌单"; metadata.playlistPosition = 4
        metadata.playlistArtworkURL = URL(string: "https://example.com/list.jpg")
        let result = try await provider.finalize(file, metadata: JSONEncoder().encode(metadata), staging: staging)
        guard case .updatingCollection(let manifest) = result.provenance else { Issue.record("Missing manifest"); return }
        let entry = try #require(manifest.entries.first)
        #expect(result.folderName == "qqmusic/歌单/歌单 [99]")
        #expect(manifest.source.provider == "qqmusic")
        #expect(manifest.source.kind == "playlist")
        #expect(manifest.source.id == "99")
        #expect(manifest.artworkURL == metadata.playlistArtworkURL)
        #expect(entry.relativePath == "04 歌曲 [mid].\(type)")
        #expect(entry.itemID == "mid")
        #expect(entry.track.id == metadata.track.id)
        #expect(entry.requestedQuality == "flac")
        let tags = try AudioTagCodec.read(staging.appendingPathComponent(entry.relativePath))
        #expect(tags.text("TITLE") == "歌曲")
        #expect(tags.text("TRACKNUMBER") == "2")
        #expect(tags.text("LYRICS") == lyrics)
        #expect(try Data(contentsOf: file) == Fixture.data("audio-local-tags.\(type)"))
    }

    @Test func invalidContainerNeverEntersLibrary() async throws {
        let root = URL.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let file = root.appendingPathComponent("error.html")
        try Data("<html>Access denied</html>".utf8).write(to: file)
        var metadata = metadata(); metadata.type = "flac"; metadata.actualQuality = "flac"
        let provider = QQMusicDownloadProvider(api: try client([]), library: OfflineLibraryStore(defaults: try defaults()), cacheScope: { "test" })
        await #expect(throws: QQMusicDownloadError.self) { try await provider.finalize(file, metadata: JSONEncoder().encode(metadata), staging: root) }
        #expect(try FileManager.default.contentsOfDirectory(atPath: root.path) == ["error.html"])
    }
}

nonisolated private final class QQDownloadProtocol: URLProtocol, @unchecked Sendable {
    static let state = Mutex<([Data], [Data])>(([], []))
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        var body = request.httpBody ?? Data()
        if body.isEmpty, let stream = request.httpBodyStream {
            stream.open(); defer { stream.close() }
            var buffer = [UInt8](repeating: 0, count: 4096)
            while stream.hasBytesAvailable {
                let count = stream.read(&buffer, maxLength: buffer.count)
                if count <= 0 { break }
                body.append(contentsOf: buffer.prefix(count))
            }
        }
        let data = Self.state.withLock { state -> Data in
            state.1.append(body)
            return state.0.isEmpty ? Data(#"{"code":-1}"#.utf8) : state.0.removeFirst()
        }
        client?.urlProtocol(self, didReceive: HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: data)
        client?.urlProtocolDidFinishLoading(self)
    }
    override func stopLoading() {}
}
