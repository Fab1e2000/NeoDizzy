import SwiftUI

@Observable
final class DizzyLabContentCache {
    let discover = DiscoverModel()
    let labels = PagedList { page in try await DizzyAPI.shared.labels(page: page) }
    var feed = FeedModel()
    var library = LibraryModel()
    @ObservationIgnored private var summaries: [String: DiscSummary] = [:]
    @ObservationIgnored private var details: [String: DiscDetailModel] = [:]
    private var stopped = false
    @ObservationIgnored private var purchasesTask: Task<Void, Never>?
    @ObservationIgnored private var warmTask: Task<Void, Never>?
    @ObservationIgnored private var artworkTask: Task<Void, Never>?
    @ObservationIgnored private var pending: [URL] = []
    @ObservationIgnored private var scheduled = Set<URL>()
    @ObservationIgnored private var generation = 0
    private let prepareArtwork: ([URL]) async -> Void

    init(prepareArtwork: @escaping ([URL]) async -> Void = { await AlbumArtworkPreload.prepareFirstScreen($0) }) {
        self.prepareArtwork = prepareArtwork
        for list in discover.lists.values {
            list.didLoad = { [weak self] discs in self?.remember(discs) }
        }
        labels.didLoad = { [weak self] labels in
            self?.remember(labels.flatMap(\.recentDiscs))
            self?.enqueue(labels.compactMap { DizzyURL.avatar($0.coverURL) })
        }
    }

    func stop() {
        stopped = true
        generation += 1
        warmTask?.cancel(); warmTask = nil
        artworkTask?.cancel(); artworkTask = nil
        purchasesTask?.cancel(); purchasesTask = nil
        pending.removeAll(); scheduled.removeAll()
        discover.lists.values.forEach { $0.cancel() }
        discover.showcase.cancel()
        labels.cancel(); feed.groups?.cancel(); library.purchases?.cancel()
        details.values.forEach { $0.detail.cancel() }; details.removeAll()
    }

    func disc(_ id: String) -> DiscDetailModel {
        if let model = details[id] { return model }
        if details.count >= 40, let oldest = details.keys.first { details[oldest] = nil }
        let model = DiscDetailModel(id: id)
        details[id] = model
        return model
    }
    func artwork(for id: String) -> URL? { summaries[id]?.coverURL }

    func remember(_ discs: [DiscSummary]) {
        guard !stopped else { return }
        for disc in discs { summaries[disc.id] = disc }
        enqueue(discs.compactMap(\.coverURL))
    }

    func accountChanged() {
        guard !stopped else { return }
        generation += 1
        warmTask?.cancel(); warmTask = nil
        feed = FeedModel(); library = LibraryModel()
        details.removeAll()
    }
    func purchasesChanged() {
        guard !stopped else { return }
        details.removeAll()
        purchasesTask?.cancel()
        purchasesTask = Task { await library.purchases?.reload(keepingItems: true) }
    }

    func prewarm(account: AccountStore) {
        guard !stopped else { return }
        feed.update(userID: account.isSessionExpired ? nil : account.account?.userID)
        library.update(userID: account.account?.userID)
        let currentGeneration = generation
        feed.groups?.didLoad = { [weak self] groups in
            guard let self, self.generation == currentGeneration else { return }
            self.enqueue(groups.compactMap { DizzyURL.avatar($0.labelCoverURL) })
        }
        library.purchases?.didLoad = { [weak self] items in
            guard let self, self.generation == currentGeneration else { return }
            self.remember(items.map(\.disc))
        }
        guard warmTask == nil else { return }
        warmTask = Task {
            // Public first pages only; all requests still go through DizzyHTTPClient's gate.
            for category in DiscCategory.allCases {
                guard !Task.isCancelled, generation == currentGeneration else { return }
                if let list = discover.lists[category], list.loadedPages == 0 { await list.loadMore() }
            }
            guard !Task.isCancelled else { return }
            if labels.loadedPages == 0 { await labels.loadMore() }
            guard !Task.isCancelled else { return }
            if let list = feed.groups, list.loadedPages == 0 { await list.loadMore() }
            guard !Task.isCancelled else { return }
            if let list = library.purchases, list.loadedPages == 0 { await list.loadMore() }
            guard !Task.isCancelled else { return }
            await discover.showcase.loadIfNeeded()
            guard !Task.isCancelled, generation == currentGeneration else { return }
            if let showcase = discover.showcase.value {
                remember(showcase.deals.map(\.disc))
                enqueue(showcase.packs.compactMap(\.coverURL))
            }
        }
    }

    private func enqueue(_ urls: [URL]) {
        guard !stopped else { return }
        pending += urls.prefix(12).filter { scheduled.insert($0).inserted }
        guard artworkTask == nil, !pending.isEmpty else { return }
        artworkTask = Task {
            defer { artworkTask = nil }
            while !pending.isEmpty && !Task.isCancelled {
                let batch = Array(pending.prefix(3))
                pending.removeFirst(batch.count)
                await prepareArtwork(batch)
            }
        }
    }
}
