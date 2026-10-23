import Foundation
import Synchronization
import Testing
@testable import NeoDizzy

@Suite(.serialized) @MainActor
struct IntegrationTransportIsolationTests {
    @Test func disablingOneClientDoesNotDisableAnother() async throws {
        IntegrationTransportIsolationTestsStub.state.withLock { $0 = .init(respond: true) }
        let dizzy = DizzyHTTPClient(session: session())
        let netease = NeteaseClient(session: session())
        await dizzy.setEnabled(false)
        let response: Response = try await netease.request("/api/test")
        #expect(response.code == 200)
        await netease.setEnabled(false)
        await dizzy.setEnabled(true)
        let data = try await dizzy.data(path: "/test")
        #expect(!data.isEmpty)
    }

    private func session() -> URLSession {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [IntegrationTransportIsolationTestsStub.self]
        return URLSession(configuration: configuration)
    }
    private func waitForRequest() async throws {
        for _ in 0..<300 {
            if IntegrationTransportIsolationTestsStub.state.withLock({ $0.started > 0 }) { return }
            try await Task.sleep(for: .milliseconds(10))
        }
        throw CancellationError()
    }
    private struct Response: Decodable { let code: Int }
}

nonisolated private final class IntegrationTransportIsolationTestsStub: URLProtocol, @unchecked Sendable {
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
