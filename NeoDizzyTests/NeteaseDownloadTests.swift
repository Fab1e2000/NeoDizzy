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
                          playbackSettings: NeteasePlaybackSettings(monitorsNetwork: false))
    }
    private var full: String { #"{"id":42,"url":"http://audio.example/song.mp3","level":"standard","type":"mp3","br":128000}"# }
    private var trial: String { #"{"id":42,"url":"http://audio.example/trial.mp3","level":"standard","type":"mp3","br":128000,"freeTrialInfo":{}}"# }

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
        let settings = NeteasePlaybackSettings(defaults: defaults, monitorsNetwork: false)
        #expect(settings.download == .lossless)
        settings.download = .master
        settings.updateNetwork(isCellular: true)
        #expect(settings.download == .master)
        #expect(NeteasePlaybackSettings(defaults: defaults, monitorsNetwork: false).download == .master)
        #expect(settings.cellular == .high)
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
