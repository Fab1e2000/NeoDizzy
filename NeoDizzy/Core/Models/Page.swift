import Foundation

/// 分页列表的一页。页码从 1 开始，与网页的 `?page=` 一致。
nonisolated struct Page<Item: Sendable>: Sendable {
    let items: [Item]
    let hasMore: Bool
}

/// 首页 HTML 里直接写好的内容：限时优惠和全部 pack。
nonisolated struct HomeShowcase: Sendable {
    let deals: [Deal]
    let packs: [PackSummary]
}

/// 搜索结果的一页。社团与用户只出现在第一页。
nonisolated struct SearchResults: Sendable {
    let labels: [SearchLabel]
    let discs: [SearchDisc]
    let hasMore: Bool
    var users: [CommunityUser] = []
}

nonisolated struct SearchLabel: Hashable, Identifiable, Sendable {
    let name: String
    let coverURL: URL?
    let description: String

    var id: String { name }
}

nonisolated struct SearchDisc: Hashable, Identifiable, Sendable {
    let disc: DiscSummary
    /// 专辑介绍的开头，网页上最多显示三行。
    let excerpt: String

    var id: String { disc.id }
}
