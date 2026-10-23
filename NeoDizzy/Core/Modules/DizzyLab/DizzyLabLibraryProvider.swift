import Foundation

extension LibraryProviderRegistry {
    func registerDizzyLab() {
        register("dizzylab", provider: Provider(title: "DizzyLab", onlineSongs: { item in
            guard item.kind == "album" else { throw ProviderError.unavailable }
            return try await DizzyAPI.shared.discDetail(id: item.itemID).tracks
        }))
    }
}
