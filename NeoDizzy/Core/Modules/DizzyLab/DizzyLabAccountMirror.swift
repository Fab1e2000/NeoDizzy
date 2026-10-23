import Foundation

extension AccountLibraryMirror {
    var dizzyLabAlbums: [MirroredCollection] { state("dizzylab").collections }
    convenience init(directory: URL, loadPurchases: @escaping (Int, Int) async throws -> Page<PurchasedDisc>) {
        self.init(directory: directory)
        legacyCollectionLoader = { [weak self] account in
            guard let self, let id = Int(account) else { return [] }
            return try await self.dizzyLabCollections(userID: id, load: loadPurchases)
        }
    }
    func registerDizzyLab(account: @escaping () -> Int?) {
        register("dizzylab", account: { account().map(String.init) }) { [weak self] _ in try await self?.syncDizzyLab(userID: account()) }
    }
    func syncDizzyLab(userID: Int?) async throws {
        try await sync("dizzylab", account: userID.map(String.init)) { commit in
            guard let userID else { return }
            let items: [MirroredCollection]
            if let loader = self.legacyCollectionLoader { items = try await loader(String(userID)) }
            else { items = try await self.dizzyLabCollections(userID: userID) { try await DizzyPages.shared.purchases(userID: $0, page: $1) } }
            try commit(items)
        }
    }
    private func dizzyLabCollections(userID: Int, load: (Int, Int) async throws -> Page<PurchasedDisc>) async throws -> [MirroredCollection] {
        var discs: [PurchasedDisc] = []
        var page = 1
        while page <= 50 {
            let result = try await load(userID, page)
            try Task.checkCancellation()
            discs += result.items
            guard result.hasMore, !result.items.isEmpty else { break }
            page += 1
        }
        var seen = Set<String>()
        return discs.filter { seen.insert($0.id).inserted }.map { purchased in
            item(providerID: "dizzylab", kind: .album, itemID: purchased.disc.id, title: purchased.disc.title,
                 subtitle: purchased.disc.labelName ?? "DizzyLab", coverURL: purchased.disc.coverURL, isPermanent: true)
        }
    }
    func isDizzyLabAlbumPurchased(_ id: String) -> Bool { dizzyLabAlbums.contains { $0.itemID == id } }
}
