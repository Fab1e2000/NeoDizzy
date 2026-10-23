import Foundation
import Synchronization
import Testing
@testable import NeoDizzy

@Suite(.serialized) @MainActor
struct NeteaseTransportIsolationTests {
    @Test func neteaseDisableCancelsPendingAndRejectsNewRequestsUntilReenabled() async throws {
        NeteaseTransportIsolationTestsStub.state.withLock { $0 = .init() }
        let client = NeteaseClient(session: session())
        client.cookie = "MUSIC_U=test-preserved"
        let pending = Task { () async throws -> Response in try await client.request("/api/test") }
        try await waitForRequest()
        await client.setEnabled(false)
        await #expect(throws: (any Error).self) { try await pending.value }
        await #expect(throws: CancellationError.self) { () async throws -> Response in try await client.request("/api/test") }
        #expect(NeteaseTransportIsolationTestsStub.state.withLock { $0.started } == 1)
        #expect(client.cookie == "MUSIC_U=test-preserved")
        NeteaseTransportIsolationTestsStub.state.withLock { $0.respond = true }
        await client.setEnabled(true)
        let response: Response = try await client.request("/api/test")
        #expect(response.code == 200)
        #expect(NeteaseTransportIsolationTestsStub.state.withLock { $0.started } == 2)
    }

    private func session() -> URLSession {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [NeteaseTransportIsolationTestsStub.self]
        return URLSession(configuration: configuration)
    }
    private func waitForRequest() async throws {
        for _ in 0..<300 {
            if NeteaseTransportIsolationTestsStub.state.withLock({ $0.started > 0 }) { return }
            try await Task.sleep(for: .milliseconds(10))
        }
        throw CancellationError()
    }
    private struct Response: Decodable { let code: Int }
}

nonisolated private final class NeteaseTransportIsolationTestsStub: URLProtocol, @unchecked Sendable {
    struct State { var respond = false; var started = 0 }
    static let state = Mutex(State())
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        let respond = Self.state.withLock { state in state.started += 1; return state.respond }
        guard respond else { return }
        let response = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: Data("{\"code\":200}".utf8))
        client?.urlProtocolDidFinishLoading(self)
    }
    override func stopLoading() {}
}
