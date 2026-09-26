import Foundation
import Testing
@testable import NeoDizzy

struct DownloadTests {
    @Test func parsesDocumentedDownloadMenuAndRejectsForeignChoices() throws {
        let options = try DownloadPageParser.parse(Fixture.text("download-options.html"), discID: "TEST-001")
        #expect(options.map(\.format) == ["128", "MP3", "FLAC"])
        #expect(options.last?.title == "FLAC (Level-5) - 145MB")
        #expect(options.allSatisfy { $0.url.host == "www.dizzylab.net" })
        #expect(try DownloadPageParser.parse(Fixture.text("download-options.html"), discID: "not-owned").isEmpty)
    }

    @Test(arguments: [
        "http://www.dizzylab.net/albums/download/?d=TEST-001&tp=MP3&k=x",
        "https://www.dizzylab.net:444/albums/download/?d=TEST-001&tp=MP3&k=x",
        "https://evil@www.dizzylab.net/albums/download/?d=TEST-001&tp=MP3&k=x",
        "https://www.dizzylab.net/other/?d=TEST-001&tp=MP3&k=x",
        "https://www.dizzylab.net/albums/download/?d=TEST-001&d=other&tp=MP3&k=x",
        "https://www.dizzylab.net/albums/download/?d=TEST-001&tp=MP3&tp=128&k=x",
        "https://www.dizzylab.net/albums/download/?d=TEST-001&tp=MP3&k=",
        "https://www.dizzylab.net/albums/download/?d=TEST-001&tp=MP3&k=x#fragment",
    ])
    func validatesWholeDownloadURL(_ string: String) throws {
        let url = try #require(URL(string: string))
        #expect(DownloadPageParser.validatedFormat(url, discID: "TEST-001") == nil)
    }

    @Test(arguments: ["../escape", "/absolute", "nested/../../escape", "C:/Windows/file", "a\\..\\b", "a//b", "a/./b", "a\u{0000}b"])
    func rejectsUnsafePaths(_ path: String) {
        #expect(throws: DownloadFailure.self) { try SafeZipExtractor.validatePath(path) }
    }

    @Test func permitsUnicodeAndNormalDirectories() throws {
        #expect(try SafeZipExtractor.validatePath("专辑/01. 星光.mp3") == "专辑/01. 星光.mp3")
        #expect(try SafeZipExtractor.validatePath("专辑/") == "专辑")
    }

    @Test(arguments: [
        ("download-utf8.zip", "专辑/01. 星光.mp3"),
        ("download-gbk.zip", "01. 星光.mp3"),
        ("download-shiftjis.zip", "01. ｦ.mp3"),
    ])
    func extractsSupportedFilenameEncodings(_ fixture: String, _ filename: String) async throws {
        let root = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let zip = root.appendingPathComponent("input.zip")
        try Fixture.data(fixture).write(to: zip)
        let destination = root.appendingPathComponent("output")
        try await SafeZipExtractor.extract(zip, into: destination)
        #expect(try Data(contentsOf: destination.appendingPathComponent(filename)) == Data("test audio placeholder".utf8))
    }

    @Test(arguments: ["download-traversal.zip", "download-symlink.zip", "download-bad-crc.zip"])
    func rejectsDangerousOrDamagedArchivesAndRemovesPartialOutput(_ fixture: String) async throws {
        let root = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let zip = root.appendingPathComponent("input.zip")
        try Fixture.data(fixture).write(to: zip)
        let destination = root.appendingPathComponent("output")
        await #expect(throws: DownloadFailure.self) { try await SafeZipExtractor.extract(zip, into: destination) }
        #expect(!FileManager.default.fileExists(atPath: destination.path))
        #expect(!FileManager.default.fileExists(atPath: root.appendingPathComponent("escape.mp3").path))
    }

    @Test func rejectsHTMLResponseAndSizeLimitBeforeImport() async throws {
        let root = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let zip = root.appendingPathComponent("input.zip")
        try Data("<!doctype html><title>Login</title>".utf8).write(to: zip)
        #expect(throws: DownloadFailure.self) { try SafeZipExtractor.validateZIP(zip) }
        try Fixture.data("download-utf8.zip").write(to: zip)
        var limits = SafeZipExtractor.Limits()
        limits.totalBytes = 1
        await #expect(throws: DownloadFailure.self) {
            try await SafeZipExtractor.extract(zip, into: root.appendingPathComponent("output"), limits: limits)
        }
    }

    @Test func cancellationDoesNotLeaveAnExtractedLibrary() async throws {
        let root = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let zip = root.appendingPathComponent("input.zip")
        try Fixture.data("download-utf8.zip").write(to: zip)
        let destination = root.appendingPathComponent("output")
        let task = Task {
            while !Task.isCancelled { await Task.yield() }
            try await SafeZipExtractor.extract(zip, into: destination)
        }
        task.cancel()
        await #expect(throws: CancellationError.self) { try await task.value }
        #expect(!FileManager.default.fileExists(atPath: destination.path))
    }

    @Test func persistedJobsContainMetadataAndNoSignedStreams() throws {
        let detail = DiscDetail(summary: DiscSummary(id: "TEST-001", title: "测试", coverURL: nil),
                                releaseDate: nil, description: "", credits: "", labelDescription: "", hasGift: false,
                                tracks: [], streams: ["1": try #require(URL(string: "https://example.com/audio?secret=do-not-save"))])
        var job = DownloadJob(id: UUID(), album: DownloadAlbum(detail), format: "FLAC")
        #expect(job.isActive)
        #expect(!job.canRetry)
        job.state = .failed
        #expect(!job.isActive)
        #expect(job.canRetry)
        let data = try JSONEncoder().encode(job)
        let text = String(decoding: data, as: UTF8.self)
        #expect(!text.contains("do-not-save"))
        #expect(!text.contains("streams"))
        #expect(try JSONDecoder().decode(DownloadJob.self, from: data).discID == "TEST-001")
        job.state = .cancelled
        #expect(job.canRetry)
        job.state = .completed
        #expect(!job.isActive && !job.canRetry)
    }

    @Test func fetchesFreshDownloadMenuWithSessionAndNoCacheReuse() async throws {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [DownloadFreshMenuProtocol.self]
        let credentials = DizzyCredentials()
        credentials.store(HTTPCookie.cookies(withResponseHeaderFields: ["Set-Cookie": "sessionid=test-session; Path=/"], for: DizzyURL.site))
        let pages = DizzyPages(client: DizzyHTTPClient(session: URLSession(configuration: configuration), credentials: credentials))
        let first = try await pages.downloadOptions(discID: "TEST-001")
        let second = try await pages.downloadOptions(discID: "TEST-001")
        #expect(first.count == 1 && second.count == 1)
        #expect(first.first?.url != second.first?.url)
    }

    @Test func resolvesHeadersWithoutDownloadingTheBody() async throws {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [DownloadHeadersOnlyProtocol.self]
        let url = try #require(URL(string: "https://download-test.invalid/album.zip"))
        // The protocol never finishes loading and never sends a byte. A buffered data task would hang.
        let resolved = try await DownloadLinkResolver.resolve(url, credentials: DizzyCredentials(), configuration: configuration)
        #expect(resolved == url)
    }

    @Test func resolverRejectsHTMLAndStripsCredentialsFromCDNRequests() async throws {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [DownloadHeadersOnlyProtocol.self]
        let url = try #require(URL(string: "https://download-test.invalid/login.html"))
        await #expect(throws: DownloadFailure.self) {
            try await DownloadLinkResolver.resolve(url, credentials: DizzyCredentials(), configuration: configuration)
        }
        let resolver = DownloadLinkResolver(cookie: "sessionid=private")
        let site = try #require(URL(string: "https://www.dizzylab.net/albums/download/"))
        #expect(resolver.request(for: site).value(forHTTPHeaderField: "Cookie") == "sessionid=private")
        #expect(resolver.request(for: url).value(forHTTPHeaderField: "Cookie") == nil)
    }

    @Test func resolvesAmbiguousJapaneseEncodingWithPublishedTrackTitle() async throws {
        let root = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let zip = root.appendingPathComponent("input.zip")
        try Fixture.data("download-shiftjis-ambiguous.zip").write(to: zip)
        let destination = root.appendingPathComponent("output")
        let track = Track(discID: "TEST", number: "1", title: "夜空", artists: "", albumTitle: "", coverURL: nil)
        try await SafeZipExtractor.extract(zip, into: destination, expectedTracks: [track])
        #expect(FileManager.default.fileExists(atPath: destination.appendingPathComponent("夜空.flac").path))
        await #expect(throws: DownloadFailure.self) {
            try await SafeZipExtractor.extract(zip, into: root.appendingPathComponent("ambiguous"))
        }
    }

    private func temporaryDirectory() throws -> URL {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        return root
    }
}

/// Delivers headers only. Successful resolution proves that no body or end-of-stream is required.
nonisolated private final class DownloadHeadersOnlyProtocol: URLProtocol, @unchecked Sendable {
    override class func canInit(with request: URLRequest) -> Bool { request.url?.host == "download-test.invalid" }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        let url = request.url!
        let type = url.pathExtension == "html" ? "text/html" : "application/zip"
        let response = HTTPURLResponse(url: url, statusCode: 200, httpVersion: "HTTP/1.1",
                                       headerFields: ["Content-Type": type, "Content-Length": "4000000000"])!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
    }
    override func stopLoading() { }
}

@MainActor
struct DownloadBackgroundBridgeTests {
    @Test func completesExactlyOnceInEitherCallbackOrder() {
        var count = 0
        BackgroundDownloadBridge.handleEvents(identifier: BackgroundDownloadBridge.identifier) { count += 1 }
        #expect(count == 0)
        BackgroundDownloadBridge.finishEvents()
        #expect(count == 1)

        BackgroundDownloadBridge.finishEvents()
        #expect(count == 1)
        BackgroundDownloadBridge.handleEvents(identifier: BackgroundDownloadBridge.identifier) { count += 1 }
        #expect(count == 2)

        BackgroundDownloadBridge.handleEvents(identifier: "other.session") { count += 1 }
        #expect(count == 3)
        BackgroundDownloadBridge.handleEvents(identifier: BackgroundDownloadBridge.identifier) { count += 1 }
        BackgroundDownloadBridge.finishEvents()
        #expect(count == 4)
    }
}

nonisolated private final class DownloadFreshMenuProtocol: URLProtocol, @unchecked Sendable {
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        #expect(request.cachePolicy == .reloadIgnoringLocalCacheData)
        #expect(request.value(forHTTPHeaderField: "Cookie") == "sessionid=test-session")
        let body = Data("<a href='/albums/download/?d=TEST-001&amp;tp=MP3&amp;k=\(UUID().uuidString)'>MP3</a>".utf8)
        let response = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: "HTTP/1.1",
                                       headerFields: ["Content-Type": "text/html", "Cache-Control": "max-age=3600"])!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .allowed)
        client?.urlProtocol(self, didLoad: body)
        client?.urlProtocolDidFinishLoading(self)
    }
    override func stopLoading() { }
}
