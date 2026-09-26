import Foundation
import Testing
@testable import NeoDizzy

nonisolated private struct Item: Identifiable, Sendable {
    let id: Int
}

/// 记录请求次数。
private final class FetchCounter {
    var count = 0
}

struct PagedListTests {
    @Test func failureStopsTheSpinner() async {
        let list = PagedList<Item> { _ in throw DizzyError.network("似乎已断开与互联网的连接。") }
        await list.loadMore()
        #expect(!list.isLoading)
        #expect(list.failure != nil)
        #expect(list.items.isEmpty)
    }

    /// 视图在加载途中离开屏幕（例如转场）时，请求照常完成，不会停在「加载中」。
    @Test func loadSurvivesCancelledViewTask() async throws {
        let list = PagedList<Item> { page in
            try await Task.sleep(for: .milliseconds(50))
            return Page(items: [Item(id: page)], hasMore: false)
        }
        let viewTask = Task { await list.loadMore() }
        try await Task.sleep(for: .milliseconds(10))
        viewTask.cancel()
        await viewTask.value
        #expect(list.items.map(\.id) == [1])
        #expect(!list.isLoading)
        #expect(list.failure == nil)
    }

    @Test func concurrentTriggersShareOneRequest() async {
        let counter = FetchCounter()
        let list = PagedList<Item> { page in
            counter.count += 1
            try await Task.sleep(for: .milliseconds(20))
            return Page(items: [Item(id: page)], hasMore: true)
        }
        async let first: Void = list.loadMore()
        async let second: Void = list.loadMore()
        _ = await (first, second)
        #expect(counter.count == 1)
        #expect(list.items.map(\.id) == [1])
    }

    @Test func reloadDropsOldResults() async {
        let counter = FetchCounter()
        let list = PagedList<Item> { page in
            counter.count += 1
            return Page(items: [Item(id: counter.count * 10 + page)], hasMore: true)
        }
        await list.loadMore()
        await list.loadMore()
        await list.reload()
        #expect(list.items.map(\.id) == [31])
    }
}

struct LoadableTests {
    @Test func loadSurvivesCancelledViewTask() async throws {
        let state = Loadable {
            try await Task.sleep(for: .milliseconds(50))
            return "内容"
        }
        let viewTask = Task { await state.loadIfNeeded() }
        try await Task.sleep(for: .milliseconds(10))
        viewTask.cancel()
        await viewTask.value
        #expect(state.value == "内容")
        #expect(!state.isLoading)
    }

    @Test func failureCanBeRetried() async {
        let counter = FetchCounter()
        let state = Loadable<String> {
            counter.count += 1
            if counter.count == 1 { throw DizzyError.network("离线") }
            return "内容"
        }
        await state.loadIfNeeded()
        #expect(state.failure != nil)
        #expect(!state.isLoading)
        await state.load()
        #expect(state.value == "内容")
        #expect(state.failure == nil)
    }
}

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
