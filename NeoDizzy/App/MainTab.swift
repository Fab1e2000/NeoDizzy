import Foundation

/// 标签栏上的主页面。搜索入口位于发现页。
enum MainTab: String, Hashable, CaseIterable, Identifiable {
    case discover, labels, feed, purchased, localLibrary

    var id: String { rawValue }

    var title: String {
        switch self {
        case .discover: String(localized: "发现")
        case .labels: String(localized: "社团")
        case .feed: String(localized: "关注")
        case .purchased: String(localized: "已购买")
        case .localLibrary: String(localized: "本地库")
        }
    }

    var systemImage: String {
        switch self {
        case .discover: "square.on.square.fill"
        case .labels: "bookmark.fill"
        case .feed: "newspaper.fill"
        case .purchased: "bag.fill"
        case .localLibrary: "music.note.list"
        }
    }

    /// 默认标签顺序。
    static let primary: [MainTab] = [.discover, .labels, .feed, .purchased, .localLibrary]
}
