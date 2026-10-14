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
