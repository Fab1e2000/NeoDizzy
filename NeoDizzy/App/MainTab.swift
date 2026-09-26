import Foundation

/// 标签栏上的主页面。搜索是系统的搜索标签，固定在标签栏末尾。
enum MainTab: String, Hashable, CaseIterable, Identifiable {
    case discover, labels, feed, library, search

    var id: String { rawValue }

    var title: String {
        switch self {
        case .discover: String(localized: "发现")
        case .labels: String(localized: "社团")
        case .feed: String(localized: "关注")
        case .library: String(localized: "音乐库")
        case .search: String(localized: "搜索")
        }
    }

    var systemImage: String {
        switch self {
        case .discover: "square.on.square.fill"
        case .labels: "bookmark.fill"
        case .feed: "newspaper.fill"
        case .library: "music.note.list"
        case .search: "magnifyingglass"
        }
    }

    /// 普通标签，按这个顺序排在搜索前面。
    static let primary: [MainTab] = [.discover, .labels, .feed, .library]
}
