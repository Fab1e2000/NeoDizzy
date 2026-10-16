import Foundation

/// 分页列表的状态，发现、社团、标签和搜索共用。页码从 1 开始。
///
/// 请求由列表自己持有，不随触发它的视图任务一起取消：视图在加载途中离开屏幕（例如转场时），
/// 请求照常完成并保存结果，不会留下「一直在加载、其实没有请求」的状态。
@Observable
final class PagedList<Item: Identifiable & Sendable> {
    private(set) var items: [Item] = []
    private(set) var hasMore = true
    private(set) var isLoading = false
    private(set) var failure: String?

    var didLoad: (([Item]) -> Void)?
    private let fetch: (Int) async throws -> Page<Item>
    private(set) var loadedPages = 0
    private var loadTask: Task<Void, Never>?
    /// 重新加载后，还没返回的旧请求作废。
    private var generation = 0
    private var needsReload = false

    init(fetch: @escaping (Int) async throws -> Page<Item>) {
        self.fetch = fetch
    }

    /// 已经加载完、而且一条都没有。
    var isEmpty: Bool { items.isEmpty && !hasMore && failure == nil }

    /// 下拉刷新可保留旧内容，避免滚动高度在请求期间塌缩。
    func reload(keepingItems: Bool = false) async {
        generation += 1
        needsReload = true
        loadTask?.cancel()
        loadTask = nil
        if !keepingItems {
            items = []
            loadedPages = 0
            hasMore = true
        }
        failure = nil
        isLoading = true
        let task = Task { await fetchNextPage(generation: generation, replacing: true) }
        loadTask = task
        await task.value
    }

    /// 加载下一页；已有请求在进行时等它完成，不重复请求。
    func loadMore() async {
        if let loadTask {
            await loadTask.value
            return
        }
        guard hasMore || needsReload else { return }
        isLoading = true
        failure = nil
        let task = Task { await fetchNextPage(generation: generation, replacing: needsReload) }
        loadTask = task
        await task.value
    }

    private func fetchNextPage(generation requestGeneration: Int, replacing: Bool = false) async {
        let page = replacing ? 1 : loadedPages + 1
        do {
            let result = try await fetch(page)
            guard requestGeneration == generation else { return }
            // 翻页期间有新作品上架时，同一张专辑可能在相邻两页各出现一次。
            var known = Set((replacing ? [] : items).map(\.id))
            let incoming = result.items.filter { known.insert($0.id).inserted }
            items = replacing ? incoming : items + incoming
            needsReload = false
            loadedPages = page
            hasMore = result.hasMore && !result.items.isEmpty
            didLoad?(incoming)
        } catch {
            guard requestGeneration == generation else { return }
            if !(error is CancellationError) {
                failure = error.localizedDescription
            }
        }
        isLoading = false
        loadTask = nil
    }
}

/// 只加载一次的内容（专辑详情、社团页、pack 页）的状态。请求同样由自己持有。
@Observable
final class Loadable<Value> {
    private(set) var value: Value?
    private(set) var failure: String?
    private(set) var isLoading = false

    private let fetch: () async throws -> Value
    private var loadTask: Task<Void, Never>?

    init(fetch: @escaping () async throws -> Value) {
        self.fetch = fetch
    }

    func loadIfNeeded() async {
        guard value == nil else { return }
        await load()
    }

    /// 加载或刷新；已有请求在进行时等它完成。
    func load() async {
        if let loadTask {
            await loadTask.value
            return
        }
        isLoading = true
        failure = nil
        let task = Task { await perform() }
        loadTask = task
        await task.value
    }

    private func perform() async {
        do {
            value = try await fetch()
        } catch is CancellationError {
        } catch {
            failure = error.localizedDescription
        }
        isLoading = false
        loadTask = nil
    }
}
