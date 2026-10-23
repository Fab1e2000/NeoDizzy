import Foundation
import Testing
@testable import NeoDizzy

/// 模拟断网：所有请求立即失败。
nonisolated private final class OfflineURLProtocol: URLProtocol, @unchecked Sendable {
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        client?.urlProtocol(self, didFailWithError: URLError(.notConnectedToInternet))
    }
    override func stopLoading() {}
}

struct HTTPClientTests {
    @Test func offlineRequestBecomesNetworkError() async {
        let configuration = URLSessionConfiguration.dizzy
        configuration.protocolClasses = [OfflineURLProtocol.self]
        let client = DizzyHTTPClient(session: URLSession(configuration: configuration))
        do {
            _ = try await client.data(path: "/")
            Issue.record("断网时请求应当失败")
        } catch let error as DizzyError {
            guard case .network = error else {
                Issue.record("应当是网络错误，实际是 \(error)")
                return
            }
        } catch {
            Issue.record("应当是 DizzyError，实际是 \(error)")
        }
    }

    @Test func previewSizeConvertsToDuration() {
        // 实测：fx4 的试听 481115 字节，时长 30.04 秒；HLRVOL4 的试听 1218861 字节，时长 76.15 秒。
        #expect(abs(DizzyAPI.previewDuration(bytes: 481_115) - 30.04) < 0.2)
        #expect(abs(DizzyAPI.previewDuration(bytes: 1_218_861) - 76.15) < 0.2)
    }
}
