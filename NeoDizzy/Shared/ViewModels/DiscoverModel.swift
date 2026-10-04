import Foundation
import Observation

/// 发现页的分段，与网站首页的五个标签一致。
enum DiscoverSection: String, CaseIterable, Identifiable {
    case album, ep, dig, packs, deals

    var id: String { rawValue }

    var title: String {
        switch self {
        case .album: DiscCategory.album.title
        case .ep: DiscCategory.ep.title
        case .dig: DiscCategory.dig.title
        case .packs: "pack"
        case .deals: String(localized: "限时优惠")
        }
    }

    var category: DiscCategory? {
        switch self {
        case .album: .album
        case .ep: .ep
        case .dig: .dig
        case .packs, .deals: nil
        }
    }
}

@Observable
final class DiscoverModel {
    var section: DiscoverSection = .album

    /// 每个分段各自保留列表和滚动进度，来回切换不重新加载。
    let lists: [DiscCategory: PagedList<DiscSummary>] = Dictionary(
        uniqueKeysWithValues: DiscCategory.allCases.map { category in
            (category, PagedList { page in try await DizzyAPI.shared.discs(category, page: page) })
        }
    )
    /// 首页 HTML 里的限时优惠和 pack，一次请求同时拿到。
    private(set) var showcase = Loadable { try await DizzyPages.shared.home() }

    func refresh() async {
        if let category = section.category {
            await lists[category]?.reload()
        } else {
            showcase = Loadable { try await DizzyPages.shared.home() }
            await showcase.load()
        }
    }
}
