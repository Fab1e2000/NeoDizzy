import Foundation
import Testing
@testable import NeoDizzy

@MainActor
struct ModuleCacheLifecycleTests {
    nonisolated private struct Item: Identifiable, Sendable { let id: Int }

    @Test func cancelledPageIgnoresAnUncooperativeLateResponse() async {
        var response: CheckedContinuation<Page<Item>, Never>?
        let list = PagedList<Item> { _ in await withCheckedContinuation { response = $0 } }
        let loading = Task { await list.loadMore() }
        while response == nil { await Task.yield() }
        list.cancel()
        response?.resume(returning: Page(items: [Item(id: 1)], hasMore: false))
        await loading.value
        #expect(list.items.isEmpty)
        #expect(!list.isLoading)
        #expect(list.loadedPages == 0)
    }

    @Test func cancelledLoadCannotOverwriteANewGeneration() async {
        var response: CheckedContinuation<Int, Never>?
        var requests = 0
        let model = Loadable<Int> {
            requests += 1
            if requests == 1 { return await withCheckedContinuation { response = $0 } }
            return 2
        }
        let old = Task { await model.load() }
        while response == nil { await Task.yield() }
        model.cancel()
        await model.load()
        response?.resume(returning: 1)
        await old.value
        #expect(model.value == 2)
        #expect(!model.isLoading)
    }




}
