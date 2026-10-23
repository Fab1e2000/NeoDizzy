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
        let list = PagedList<Item> { _ in throw URLError(.notConnectedToInternet) }
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

    @Test func refreshKeepsContentUntilReplacementArrives() async {
        let counter = FetchCounter()
        var inspectRefresh: (() -> Void)?
        let list = PagedList<Item> { page in
            counter.count += 1
            if counter.count == 3 { inspectRefresh?() }
            return Page(items: [Item(id: counter.count * 10 + page)], hasMore: true)
        }
        await list.loadMore()
        await list.loadMore()
        inspectRefresh = {
            #expect(list.items.map(\.id) == [11, 22])
            #expect(list.loadedPages == 2)
            #expect(list.isLoading)
        }
        await list.reload(keepingItems: true)
        #expect(list.items.map(\.id) == [31])
        #expect(list.loadedPages == 1)
        await list.loadMore()
        #expect(list.items.map(\.id) == [31, 42])
    }

    @Test func failedRefreshRetainsContentAndRetriesFirstPage() async {
        let counter = FetchCounter()
        let list = PagedList<Item> { page in
            counter.count += 1
            if counter.count == 2 { throw URLError(.notConnectedToInternet) }
            return Page(items: [Item(id: counter.count * 10 + page)], hasMore: false)
        }
        await list.loadMore()
        await list.reload(keepingItems: true)
        #expect(list.items.map(\.id) == [11])
        #expect(list.failure != nil)
        #expect(!list.isLoading)
        await list.loadMore()
        #expect(list.items.map(\.id) == [31])
        #expect(list.failure == nil)
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
            if counter.count == 1 { throw URLError(.notConnectedToInternet) }
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
