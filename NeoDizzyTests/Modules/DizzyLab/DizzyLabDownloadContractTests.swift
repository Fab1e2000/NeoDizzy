import Foundation
import Testing
@testable import NeoDizzy

struct DizzyLabDownloadContractTests {
    @Test func parsesGiftSeparatelyFromAlbumFormats() throws {
        let html = """
        <a href="/albums/download_gift/TEST-001/?k=fixture&amp;v=2"><i class="fa fa-gift"></i></a>
        <a href="/albums/download/?d=TEST-001&amp;tp=FLAC&amp;k=fixture">FLAC</a>
        <a href="/albums/download_gift/OTHER/?k=fixture">Other</a>
        <a href="https://evil.example/albums/download_gift/TEST-001/?k=fixture">Foreign</a>
        <a href="/albums/download_gift/TEST-001/?k=duplicate">Duplicate</a>
        """
        let gifts = try DownloadPageParser.parse(html, discID: "TEST-001", gift: true)
        #expect(gifts.count == 1)
        #expect(gifts.first?.isGift == true)
        #expect(gifts.first?.title == "下载特典")
        #expect(try DownloadPageParser.parse(html, discID: "TEST-001").map(\.format) == ["FLAC"])
    }

    @Test(arguments: [
        "http://www.dizzylab.net/albums/download_gift/TEST-001/?k=x",
        "https://www.dizzylab.net:444/albums/download_gift/TEST-001/?k=x",
        "https://evil@www.dizzylab.net/albums/download_gift/TEST-001/?k=x",
        "https://www.dizzylab.net/albums/download_gift/OTHER/?k=x",
        "https://www.dizzylab.net/albums/download_gift/TEST-001/?k=",
        "https://www.dizzylab.net/albums/download_gift/TEST-001/?k=x&k=y",
        "https://www.dizzylab.net/albums/download_gift/TEST-001/?k=x#fragment",
    ])
    func rejectsInvalidGiftLinks(_ string: String) throws {
        #expect(DownloadPageParser.validatedGiftFormat(try #require(URL(string: string)), discID: "TEST-001") == nil)
    }

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
}

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
