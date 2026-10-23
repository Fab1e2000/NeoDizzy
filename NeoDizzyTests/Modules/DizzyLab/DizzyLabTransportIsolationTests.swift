import Foundation
import Synchronization
import Testing
@testable import NeoDizzy

@Suite(.serialized) @MainActor
struct DizzyLabTransportIsolationTests {
    @Test func dizzyDisableCancelsPendingPreservesCredentialsAndCanReuseSession() async throws {
        DizzyLabTransportIsolationTestsStub.state.withLock { $0 = .init() }
        let credentials = DizzyCredentials()
        credentials.setToken("test-preserved")
        let client = DizzyHTTPClient(session: session(), credentials: credentials)
        let pending = Task { try await client.data(path: "/test") }
        try await waitForRequest()
        await client.setEnabled(false)
        await #expect(throws: (any Error).self) { try await pending.value }
        await #expect(throws: CancellationError.self) { try await client.data(path: "/test") }
        #expect(DizzyLabTransportIsolationTestsStub.state.withLock { $0.started } == 1)
        #expect(credentials.token == "test-preserved")
        DizzyLabTransportIsolationTestsStub.state.withLock { $0.respond = true }
        await client.setEnabled(true)
        let data = try await client.data(path: "/test")
        #expect(try JSONDecoder().decode(Response.self, from: data).code == 200)
        #expect(DizzyLabTransportIsolationTestsStub.state.withLock { $0.started } == 2)
    }

    private func session() -> URLSession {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [DizzyLabTransportIsolationTestsStub.self]
        return URLSession(configuration: configuration)
    }
    private func waitForRequest() async throws {
        for _ in 0..<300 {
            if DizzyLabTransportIsolationTestsStub.state.withLock({ $0.started > 0 }) { return }
            try await Task.sleep(for: .milliseconds(10))
        }
        throw CancellationError()
    }
    private struct Response: Decodable { let code: Int }
}

nonisolated private final class DizzyLabTransportIsolationTestsStub: URLProtocol, @unchecked Sendable {
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
