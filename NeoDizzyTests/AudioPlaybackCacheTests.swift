import AVFoundation
import Foundation
import Synchronization
import Testing
import XCTest
@testable import NeoDizzy

@MainActor struct AudioPlaybackCacheTests {
    private func root() throws -> URL {
        let url = URL.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }
    @Test func thresholdRequiresMoreThanNinetyPercentAndKnownDuration() {
        #expect(!AudioPlaybackCache.mayContinue(listened: 90, duration: 100))
        #expect(AudioPlaybackCache.mayContinue(listened: 90.01, duration: 100))
        #expect(!AudioPlaybackCache.mayContinue(listened: 100, duration: 0))
        #expect(!AudioPlaybackCache.mayContinue(listened: .infinity, duration: 100))
        #expect(!AudioPlaybackCache.mayContinue(listened: 99, duration: .nan))
    }
    @Test func onlyCompleteFilesPersistAndQualityAndAccountAreIsolated() throws {
        let root = try root(); defer { try? FileManager.default.removeItem(at: root) }
        let cache = AudioPlaybackCache(directory: root.appendingPathComponent("cache"))
        let source = root.appendingPathComponent("test.mp3")
        try Data(repeating: 1, count: 100).write(to: source)
        let key = AudioPlaybackCache.Key(trackID: "a", scope: "account-a", quality: "hires")
        #expect(throws: (any Error).self) { try cache.commit(source, key: key, actualQuality: "exhigh", bytes: 101, fileExtension: "mp3") }
        #expect(cache.file(for: key) == nil)
        try cache.commit(source, key: key, actualQuality: "exhigh", bytes: 100, fileExtension: "mp3")
        #expect(cache.entry(for: key)?.actualQuality == "exhigh")
        #expect(cache.file(for: .init(trackID: "a", scope: "account-b", quality: "hires")) == nil)
        #expect(cache.file(for: .init(trackID: "a", scope: "account-a", quality: "lossless")) == nil)
        let restored = AudioPlaybackCache(directory: cache.directory)
        #expect(restored.file(for: key) != nil)
        let file = try #require(restored.file(for: key))
        try Data([1]).write(to: file)
        #expect(restored.file(for: key) == nil)
    }
    @Test func capacityEvictsLeastRecentlyUsedAndClearPreservesActivePlayback() throws {
        let root = try root(); defer { try? FileManager.default.removeItem(at: root) }
        let cache = AudioPlaybackCache(directory: root.appendingPathComponent("cache"), capacity: 20)
        let source = root.appendingPathComponent("source.mp3")
        try Data(repeating: 0, count: 10).write(to: source)
        func key(_ id: String) -> AudioPlaybackCache.Key { .init(trackID: id, scope: "a", quality: "high") }
        for id in ["1", "2"] { try cache.commit(source, key: key(id), actualQuality: "high", bytes: 10, fileExtension: "mp3") }
        _ = cache.file(for: key("1"))
        try cache.commit(source, key: key("3"), actualQuality: "high", bytes: 10, fileExtension: "mp3")
        #expect(cache.file(for: key("2")) == nil)
        let playing = try #require(cache.file(for: key("1")))
        cache.protect(playing); cache.clear()
        #expect(cache.bytes == 0)
        #expect(cache.file(for: key("1")) == nil)
        #expect(FileManager.default.fileExists(atPath: playing.path))
        #expect(FileManager.default.fileExists(atPath: source.path))
        cache.protect(nil)
        #expect(!FileManager.default.fileExists(atPath: playing.path))
    }
    @Test func listeningClockExcludesPauseAndDoesNotUseSeekPosition() {
        var clock = 0.0
        let reporting = PlaybackReportingSession(now: { clock })
        reporting.begin(Track(discID: "1", number: "1", title: "", artists: "", albumTitle: "", coverURL: nil), sourceID: nil)
        reporting.setPlaying(true); clock = 20; reporting.setPlaying(false)
        clock = 500
        #expect(reporting.listenedSeconds == 20)
        reporting.setPlaying(true); clock = 571
        #expect(AudioPlaybackCache.mayContinue(listened: reporting.listenedSeconds, duration: 100))
    }
}

@MainActor final class ProgressiveAudioLoaderTests: XCTestCase {
    func testOneTransferFeedsPlaybackAndProducesCompleteFile() async throws {
        let result = try await run(status: 200, extraBytes: 0)
        XCTAssertTrue(result)
    }
    func testTruncatedResponseIsNeverPublished() async throws {
        let result = try await run(status: 200, extraBytes: 100)
        XCTAssertFalse(result)
    }
    func testHTTPFailureIsNeverPublished() async throws {
        let result = try await run(status: 403, extraBytes: 0)
        XCTAssertFalse(result)
    }
    func testSwitchingCancelsAtNinetyPercentButAllowsBeyondThreshold() async throws {
        for listened in [90.0, 91.0] {
            let root = URL.temporaryDirectory.appendingPathComponent(UUID().uuidString)
            defer { try? FileManager.default.removeItem(at: root) }
            let cache = AudioPlaybackCache(directory: root)
            let configuration = URLSessionConfiguration.ephemeral
            configuration.protocolClasses = [HeldAudioStream.self]
            let began = expectation(description: "request began")
            let stopped = expectation(description: "request cancelled")
            HeldAudioStream.callbacks.withLock { $0 = ({ began.fulfill() }, { stopped.fulfill() }) }
            let key = AudioPlaybackCache.Key(trackID: "song", scope: "test", quality: "high")
            let (item, id) = try XCTUnwrap(cache.makeItem(url: URL(string: "https://cache-test.invalid/held.mp3")!, key: key, actualQuality: "high", configuration: configuration))
            let loading = Task { try? await item.asset.load(.duration) }
            await fulfillment(of: [began], timeout: 5)
            cache.leave(id, listened: listened, duration: 100)
            if listened > 90 {
                // It must still be in flight until explicit cache cleanup.
                try await Task.sleep(for: .milliseconds(100))
                XCTAssertEqual(HeldAudioStream.stops.withLock { $0 }, 0)
                cache.clear()
            }
            await fulfillment(of: [stopped], timeout: 5)
            XCTAssertNil(cache.file(for: key))
            loading.cancel()
        }
    }

    private func run(status: Int, extraBytes: Int) async throws -> Bool {
        let root = URL.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let audio = try Fixture.data("audio-local-tags.mp3")
        AudioStreamStub.state.withLock { $0 = (audio, status, extraBytes, 0) }
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [AudioStreamStub.self]
        let complete = expectation(description: "transfer finished")
        let output = Mutex<URL?>(nil)
        let loader = try ProgressiveAudioLoader(url: URL(string: "https://cache-test.invalid/audio.mp3")!, directory: root, configuration: configuration) { file, _, _ in
            output.withLock { $0 = file }; complete.fulfill()
        }
        let item = loader.makeItem()
        let loading = Task { try? await item.asset.load(.duration) }
        await fulfillment(of: [complete], timeout: 10)
        let file = output.withLock { $0 }
        if let file {
            XCTAssertEqual(try Data(contentsOf: file), audio)
            let duration = await loading.value
            XCTAssertGreaterThan(duration?.seconds ?? 0, 0)
        } else { loading.cancel() }
        XCTAssertEqual(AudioStreamStub.state.withLock { $0.3 }, 1)
        withExtendedLifetime(loader) { }
        return file != nil
    }
}
nonisolated private final class AudioStreamStub: URLProtocol, @unchecked Sendable {
    static let state = Mutex<(Data, Int, Int, Int)>((Data(), 200, 0, 0))
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        let (data, status, extra, _) = Self.state.withLock { $0.3 += 1; return $0 }
        let response = HTTPURLResponse(url: request.url!, statusCode: status, httpVersion: nil,
                                       headerFields: ["Content-Type": "audio/mpeg", "Content-Length": String(data.count + extra)])!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: data)
        client?.urlProtocolDidFinishLoading(self)
    }
    override func stopLoading() {}
}

nonisolated private final class HeldAudioStream: URLProtocol, @unchecked Sendable {
    static let callbacks = Mutex<(@Sendable () -> Void, @Sendable () -> Void)>(({}, {}))
    static let stops = Mutex(0)
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        Self.stops.withLock { $0 = 0 }
        client?.urlProtocol(self, didReceive: HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil,
            headerFields: ["Content-Type": "audio/mpeg", "Content-Length": "100000"])!, cacheStoragePolicy: .notAllowed)
        Self.callbacks.withLock { $0.0 }()
    }
    override func stopLoading() {
        Self.stops.withLock { $0 += 1 }
        Self.callbacks.withLock { $0.1 }()
    }
}
