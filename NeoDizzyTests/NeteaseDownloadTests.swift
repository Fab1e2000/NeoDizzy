import Foundation
import Synchronization
import Testing
@testable import NeoDizzy

@Suite(.serialized) @MainActor
struct NeteaseDownloadTests {
    private func api(_ responses: [String]) -> NeteaseAPI {
        DownloadSourceStub.queue.withLock { $0 = (responses, []) }
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [DownloadSourceStub.self]
        return NeteaseAPI(client: NeteaseClient(session: URLSession(configuration: configuration)),
                          playbackSettings: NeteasePlaybackSettings())
    }
    private var full: String { #"{"id":42,"url":"http://audio.example/song.mp3","level":"standard","type":"mp3","br":128000}"# }
    private var trial: String { #"{"id":42,"url":"http://audio.example/trial.mp3","level":"standard","type":"mp3","br":128000,"freeTrialInfo":{}}"# }

    @Test func reusesCompleteListeningCacheWithoutRequestingAnotherURL() async throws {
        let api = api([])
        api.client.cookie = "test-cache-\(UUID())"
        let suite = "CacheDownload.\(UUID())"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let track = Track(discID: "7", number: "1", title: "Cached", artists: "", albumTitle: "", coverURL: nil,
                          remoteSource: RemoteTrackSource(providerID: "netease", itemID: "42"))
        let key = api.cacheKey(for: track.id, quality: .hiResolution)
        let file = URL.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".mp3")
        let data = try Fixture.data("audio-local-tags.mp3")
        try data.write(to: file)
        defer { AudioPlaybackCache.shared.remove(key); try? FileManager.default.removeItem(at: file) }
        try AudioPlaybackCache.shared.commit(file, key: key, actualQuality: "exhigh", bytes: Int64(data.count), fileExtension: "mp3")
        let provider = NeteaseDownloadProvider(api: api, library: OfflineLibraryStore(defaults: defaults))
        let metadata = NeteaseDownloadMetadata(track: track, albumArtist: "", trackNumber: 1, discNumber: 1, quality: .hiResolution)
        let transfer = DownloadTransfer(id: UUID(), metadata: try JSONEncoder().encode(metadata))
        let result = try #require(try await provider.source(transfer))
        #expect(result.url.isFileURL)
        #expect(try Data(contentsOf: result.url) == data)
        #expect(try JSONDecoder().decode(NeteaseDownloadMetadata.self, from: result.metadata).actualQuality == "exhigh")
        #expect(DownloadSourceStub.queue.withLock { $0.1.isEmpty })
    }

    @Test func rejectsTrialOnBothRoutesAndUsesPlaybackFallback() async throws {
        let api = api(["{\"code\":200,\"data\":\(trial)}", "{\"code\":200,\"data\":[\(full)]}"])
        let source = try await api.downloadSource(42, quality: .standard)
        #expect(source.url.scheme == "https")
        #expect(source.level == "standard")
        #expect(source.bitrate == 128000)
        let paths = DownloadSourceStub.queue.withLock { $0.1 }
        #expect(paths == ["/eapi/song/enhance/download/url/v1", "/eapi/song/enhance/player/url/v1"])
        let onlyTrials = self.api(["{\"code\":200,\"data\":\(trial)}", "{\"code\":200,\"data\":[\(trial)]}"])
        await #expect(throws: DownloadFailure.self) { try await onlyTrials.downloadSource(42, quality: .standard) }
    }
    @Test func exhaustsDedicatedQualityFallbackBeforePlaybackRoute() async throws {
        let api = api([#"{"code":403}"#, #"{"code":403}"#, "{\"code\":200,\"data\":[\(trial)]}", "{\"code\":200,\"data\":[\(full)]}"])
        _ = try await api.downloadSource(42, quality: .high)
        #expect(DownloadSourceStub.queue.withLock { $0.1.map { $0.contains("download") } } == [true, true, false, false])
    }
    @Test(arguments: ["flac", "mp3"])
    func finalizesNCMWithTagsAndManifest(_ format: String) async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let staging = root.appendingPathComponent("staging")
        try FileManager.default.createDirectory(at: staging, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let source = root.appendingPathComponent("download.archive")
        try Fixture.data("audio-ncm-\(format).ncm").write(to: source)
        let suite = "NCMFinalize.\(UUID())"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let provider = NeteaseDownloadProvider(api: api([#"{"code":200,"lrc":{"lyric":"[00:01]测试歌词"}}"#]),
                                              library: OfflineLibraryStore(defaults: defaults))
        let track = Track(discID: "7", number: "2", title: "测试歌曲", artists: "歌手", albumTitle: "专辑",
                          coverURL: nil, remoteSource: RemoteTrackSource(providerID: "netease", itemID: "42"))
        let metadata = NeteaseDownloadMetadata(track: track, albumArtist: "专辑歌手", trackNumber: 2,
                                               discNumber: 1, quality: .lossless, actualQuality: "lossless", type: "ncm")
        let prepared = try await provider.finalize(source, metadata: JSONEncoder().encode(metadata), staging: staging)
        guard case .collection(let manifest, _, _, _) = prepared.provenance else {
            Issue.record("Missing collection manifest"); return
        }
        #expect(prepared.folderName == "netease/专辑/专辑")
        let entry = try #require(manifest.entries.first)
        #expect(entry.relativePath == "02 测试歌曲 [42].\(format)")
        let tags = try AudioTagCodec.read(staging.appendingPathComponent(entry.relativePath))
        #expect(tags.text("TITLE") == "测试歌曲")
        #expect(tags.text("LYRICS") == "[00:01]测试歌词")
        #expect(try FileManager.default.contentsOfDirectory(atPath: staging.path) == [entry.relativePath])
    }

    private func plannedPlaylist(_ provider: NeteaseDownloadProvider) async throws -> [NeteaseDownloadMetadata] {
        let payload = try JSONEncoder().encode(NeteaseDownloadRequest(kind: "playlist", id: 99, quality: .standard))
        let request = DownloadRequest(title: "歌单", identity: "playlist/99", coverURL: nil, payload: payload)
        return try await provider.plan(JSONEncoder().encode(request)).map { try JSONDecoder().decode(NeteaseDownloadMetadata.self, from: $0.metadata) }
    }
    private func song(_ id: Int, album: Int, number: Int?) -> String {
        #"{"id":\#(id),"name":"歌\#(id)","ar":[{"id":1,"name":"歌手"}],"al":{"id":\#(album),"name":"专辑\#(album)"}"#
            + (number.map { #","no":\#($0)}"# } ?? "}")
    }
    private var playlistResponse: String { #"{"code":200,"playlist":{"id":99,"name":"歌单","trackIds":[{"id":1},{"id":2},{"id":3}]}}"# }

    @Test func playlistPlanReusesSongDetailTrackNumbers() async throws {
        let suite = "PlaylistPlan.\(UUID())"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let songs = [song(1, album: 7, number: 4), song(2, album: 8, number: 2), song(3, album: 9, number: 1)]
        let provider = NeteaseDownloadProvider(api: api([playlistResponse, #"{"code":200,"songs":[\#(songs.joined(separator: ","))]}"#]),
                                              library: OfflineLibraryStore(defaults: defaults))
        let metadata = try await plannedPlaylist(provider)
        #expect(metadata.map(\.trackNumber) == [4, 2, 1])
        #expect(metadata.map(\.playlistPosition) == [1, 2, 3])
        #expect(DownloadSourceStub.queue.withLock { $0.1.filter { $0.contains("album") } }.isEmpty)
    }

    @Test func playlistPlanLooksUpEachMissingAlbumOnce() async throws {
        let suite = "PlaylistPlanLookup.\(UUID())"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let songs = [song(1, album: 7, number: nil), song(2, album: 7, number: nil), song(3, album: 8, number: 5)]
        let album = #"{"code":200,"album":{"id":7,"name":"专辑7","artist":{"id":5,"name":"专辑歌手"}},"songs":[\#(song(2, album: 7, number: nil)),\#(song(1, album: 7, number: nil))]}"#
        let provider = NeteaseDownloadProvider(api: api([playlistResponse, #"{"code":200,"songs":[\#(songs.joined(separator: ","))]}"#, album]),
                                              library: OfflineLibraryStore(defaults: defaults))
        let metadata = try await plannedPlaylist(provider)
        #expect(metadata.map(\.trackNumber) == [2, 1, 5])
        #expect(metadata.map(\.albumArtist) == ["专辑歌手", "专辑歌手", "歌手"])
        #expect(DownloadSourceStub.queue.withLock { $0.1.filter { $0.contains("album") } } .count == 1)
    }

    @Test func artworkFailureKeepsDownloadedAudio() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let staging = root.appendingPathComponent("staging")
        try FileManager.default.createDirectory(at: staging, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let source = root.appendingPathComponent("download.archive")
        try Fixture.data("audio-ncm-mp3.ncm").write(to: source)
        let suite = "ArtworkFailure.\(UUID())"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [ArtworkFailureStub.self]
        let provider = NeteaseDownloadProvider(api: api([#"{"code":200}"#]), library: OfflineLibraryStore(defaults: defaults),
                                              artworkSession: URLSession(configuration: configuration))
        let track = Track(discID: "7", number: "2", title: "测试歌曲", artists: "歌手", albumTitle: "专辑",
                          coverURL: URL(string: "https://p1.music.126.net/cover.jpg"),
                          remoteSource: RemoteTrackSource(providerID: "netease", itemID: "42"))
        let metadata = NeteaseDownloadMetadata(track: track, albumArtist: "歌手", trackNumber: 2,
                                               discNumber: 1, quality: .standard, actualQuality: "standard", type: "ncm")
        let prepared = try await provider.finalize(source, metadata: JSONEncoder().encode(metadata), staging: staging)
        guard case .collection(let manifest, _, _, _) = prepared.provenance else {
            Issue.record("Missing collection manifest"); return
        }
        let entry = try #require(manifest.entries.first)
        let tags = try AudioTagCodec.read(staging.appendingPathComponent(entry.relativePath))
        #expect(tags.text("TITLE") == "测试歌曲")
    }

    @Test func albumDownloadsPreserveSameNamedTracksAcrossDiscs() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let suite = "MultiDiscDownload.\(UUID())"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let library = OfflineLibraryStore(defaults: defaults,
            scanner: LocalLibraryScanner(cacheURL: root.appendingPathComponent(".cache")), libraryRoot: root)
        let provider = NeteaseDownloadProvider(api: api([
            #"{"code":200}"#, #"{"code":200}"#
        ]), library: library)
        for disc in [1, 2] {
            let staging = root.appendingPathComponent(".staging")
            try FileManager.default.createDirectory(at: staging, withIntermediateDirectories: true)
            let source = root.appendingPathComponent(".download")
            try Fixture.data("audio-ncm-flac.ncm").write(to: source)
            let track = Track(discID: "7", number: "1", title: "序曲", artists: "歌手", albumTitle: "多碟专辑",
                coverURL: nil, remoteSource: RemoteTrackSource(providerID: "netease", itemID: String(disc)))
            let metadata = NeteaseDownloadMetadata(track: track, albumArtist: "歌手", trackNumber: 1,
                discNumber: disc, quality: .lossless, actualQuality: "lossless", type: "ncm")
            let prepared = try await provider.finalize(source, metadata: JSONEncoder().encode(metadata), staging: staging)
            try await library.commit(staging: staging, folderName: prepared.folderName, provenance: prepared.provenance)
            try FileManager.default.removeItem(at: staging)
        }
        let album = try #require(library.collection(provider: "netease", kind: "album", id: "7"))
        #expect(Set(album.manifest.entries.map(\.itemID)) == ["1", "2"])
        #expect(Set(album.manifest.entries.map(\.relativePath)) == ["01 序曲 [1].flac", "01 序曲 [2].flac"])
        for entry in album.manifest.entries {
            let file = try #require(album.localFile(for: entry.track))
            #expect(try AudioTagCodec.read(file).text("DISCNUMBER") == entry.itemID)
        }
    }

    @Test func playlistDownloadsStayTogetherAndRemainPlayableOutsideAlbums() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let suite = "PlaylistDownload.\(UUID())"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let library = OfflineLibraryStore(defaults: defaults,
            scanner: LocalLibraryScanner(cacheURL: root.appendingPathComponent(".cache")), libraryRoot: root)
        let provider = NeteaseDownloadProvider(api: api([]), library: library)
        let originalTrack = Track(discID: "1", number: "1", title: "同名歌曲", artists: "歌手", albumTitle: "原专辑1", coverURL: nil,
                                  remoteSource: RemoteTrackSource(providerID: "netease", itemID: "1"))
        let originalDirectory = root.appendingPathComponent("原专辑1")
        try FileManager.default.createDirectory(at: originalDirectory, withIntermediateDirectories: true)
        let originalFile = originalDirectory.appendingPathComponent("01.flac")
        let originalBytes = try Fixture.data("audio-local-tags.flac")
        try originalBytes.write(to: originalFile)
        let originalManifest = LibraryManifest(source: LibrarySource(provider: "netease", kind: "album", id: "1"), title: "原专辑1", artist: "歌手",
            entries: [.init(relativePath: "01.flac", itemID: "1", track: originalTrack)])
        try JSONEncoder().encode(originalManifest).write(to: originalDirectory.appendingPathComponent(LibraryManifest.filename))
        try LocalPlaylistFile.write(title: "我的歌单", entries: [(originalTrack, originalFile)],
            source: LibrarySource(provider: "netease", kind: "playlist", id: "99"), existing: nil, root: root)
        await library.scan()
        var remoteTracks: [Track] = []
        // Commit out of order, with identical song titles and original track numbers.
        for position in [2, 1] {
            let staging = root.appendingPathComponent(".staging")
            try FileManager.default.createDirectory(at: staging, withIntermediateDirectories: true)
            let source = root.appendingPathComponent(".download")
            try Fixture.data("audio-ncm-flac.ncm").write(to: source)
            let track = Track(discID: String(position), number: "1", title: "同名歌曲", artists: "歌手", albumTitle: "原专辑\(position)",
                              coverURL: nil, remoteSource: RemoteTrackSource(providerID: "netease", itemID: String(position)))
            remoteTracks.append(track)
            let metadata = NeteaseDownloadMetadata(track: track, albumArtist: "歌手", trackNumber: 1, discNumber: 1,
                quality: .lossless, actualQuality: "lossless", type: "ncm", playlistID: "99", playlistTitle: "我的歌单", playlistPosition: position, playlistArtworkURL: URL(string: "https://example.com/playlist.jpg"))
            if position == 1 {
                let downloadProvider = NeteaseDownloadProvider(api: api(["{\"code\":200,\"data\":\(full.replacingOccurrences(of: "42", with: "1"))}"]), library: library)
                let transfer = DownloadTransfer(id: UUID(), metadata: try JSONEncoder().encode(metadata), state: .queued)
                #expect(try await downloadProvider.source(transfer) != nil)
            }
            let prepared = try await provider.finalize(source, metadata: JSONEncoder().encode(metadata), staging: staging)
            #expect(prepared.folderName == "netease/歌单/我的歌单")
            try await library.commit(staging: staging, folderName: prepared.folderName, provenance: prepared.provenance)
            try FileManager.default.removeItem(at: staging)
            #expect(library.visibleAlbums.map(\.title) == ["原专辑1"])
            #expect(library.localPlaylists.count == 1)
        }
        let playlist = try #require(library.localPlaylists.first)
        #expect(playlist.coverURL?.absoluteString == "https://example.com/playlist.jpg")
        #expect(playlist.tracks.count == 2)
        #expect(playlist.tracks.compactMap { library.localFile(for: $0)?.lastPathComponent } == ["01 同名歌曲 [1].flac", "02 同名歌曲 [2].flac"])
        #expect(remoteTracks.allSatisfy { library.localFile(for: $0) != nil })
        #expect(library.collections.filter { $0.manifest.source.kind == "playlist" }.count == 1)
        // Adding to a downloaded playlist preserves its files and source identity.
        try await library.add(playlist.tracks[0], to: playlist)
        #expect(library.localPlaylists.count == 1)
        #expect(library.localPlaylists[0].tracks.count == 2)
        try await library.deletePlaylist(library.localPlaylists[0])
        #expect(library.localPlaylists.isEmpty)
        #expect(library.visibleAlbums.map(\.title) == ["原专辑1"])
        #expect(library.localFile(for: remoteTracks[0]) == nil)
        #expect(try Data(contentsOf: originalFile) == originalBytes)
    }

    @Test func acceptsNCMDownloadSource() async throws {
        let body = full.replacingOccurrences(of: "mp3", with: "ncm")
        let source = try await api(["{\"code\":200,\"data\":\(body)}"]).downloadSource(42, quality: .standard)
        #expect(source.type == "ncm")
        #expect(DownloadSourceStub.queue.withLock { $0.1.count } == 1)
    }

    @Test func downloadQualityIsIndependentAndPersists() throws {
        let suite = "NeteaseDownloadTests.\(UUID())"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let settings = NeteasePlaybackSettings(defaults: defaults)
        #expect(settings.quality == .high)
        settings.quality = .master
        #expect(settings.quality == .master)
        #expect(NeteasePlaybackSettings(defaults: defaults).quality == .master)
        #expect(settings.selected == .master)
    }
    @Test(arguments: ["flac", "mp3", "m4a"])
    func writesPortableLyricsTags(_ format: String) throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("\(UUID()).\(format)")
        defer { try? FileManager.default.removeItem(at: url) }
        try Fixture.data("audio-local-tags.\(format)").write(to: url)
        let original = try AudioTagCodec.read(url)
        var draft = original
        draft.setText("LYRICS", "[00:01.00]歌词测试")
        try AudioTagCodec.write(draft, original: original, to: url)
        #expect(try AudioTagCodec.read(url).text("LYRICS") == "[00:01.00]歌词测试")
    }
}

nonisolated private final class DownloadSourceStub: URLProtocol, @unchecked Sendable {
    static let queue = Mutex<([String], [String])>(([], []))
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        let body = Self.queue.withLock { state -> String in
            state.1.append(request.url?.path ?? "")
            return state.0.isEmpty ? #"{"code":404}"# : state.0.removeFirst()
        }
        client?.urlProtocol(self, didReceive: HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: Data(body.utf8))
        client?.urlProtocolDidFinishLoading(self)
    }
    override func stopLoading() {}
}

nonisolated private final class ArtworkFailureStub: URLProtocol, @unchecked Sendable {
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        client?.urlProtocol(self, didReceive: HTTPURLResponse(url: request.url!, statusCode: 503, httpVersion: nil, headerFields: nil)!, cacheStoragePolicy: .notAllowed)
        client?.urlProtocolDidFinishLoading(self)
    }
    override func stopLoading() {}
}
