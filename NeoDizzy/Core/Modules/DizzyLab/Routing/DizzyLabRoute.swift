import Foundation

extension ModuleID {
    static let dizzyLab = ModuleID(rawValue: "dizzyLab")
}

enum DizzyLabRoute: Hashable {
    case section(DizzyLabSection)
    case disc(String), label(String), tag(String), pack(String)
    case user(Int), review(Int), discCommunity(String)
    case search(String)

    var title: String {
        switch self {
        case .section(let section): section.title
        case .disc: String(localized: "专辑")
        case .label(let name): name
        case .user: String(localized: "用户主页")
        case .tag(let tag): "#\(tag)"
        case .pack: String(localized: "合集")
        case .review: "repo 长评"
        case .discCommunity: String(localized: "社区")
        case .search: String(localized: "搜索")
        }
    }
}

// Compatibility factories keep existing links and the macOS UI source-compatible.
// New providers add their own route payloads and factories outside the host.
extension AppRoute {
    private static func dizzyLabRoute(_ route: DizzyLabRoute) -> Self {
        Self(moduleID: .dizzyLab, destination: route, title: route.title)
    }
    static func dizzyLab(_ section: DizzyLabSection) -> Self { dizzyLabRoute(.section(section)) }
    static func disc(id: String) -> Self { dizzyLabRoute(.disc(id)) }
    static func label(name: String) -> Self { dizzyLabRoute(.label(name)) }
    static func tag(_ tag: String) -> Self { dizzyLabRoute(.tag(tag)) }
    static func pack(id: String) -> Self { dizzyLabRoute(.pack(id)) }
    static func user(id: Int) -> Self { dizzyLabRoute(.user(id)) }
    static func review(id: Int) -> Self { dizzyLabRoute(.review(id)) }
    static func discCommunity(id: String) -> Self { dizzyLabRoute(.discCommunity(id)) }
    static func dizzyLabSearch(_ query: String) -> Self { dizzyLabRoute(.search(query)) }
}

/// 模块首页的四个功能入口；作品分类仍由 DiscoverSection 管理。
enum DizzyLabSection: String, CaseIterable, Identifiable {
    case shuffle, labels, feed, purchased

    var id: String { rawValue }
    var tab: MainTab {
        switch self {
        case .shuffle: .shuffle
        case .labels: .labels
        case .feed: .feed
        case .purchased: .purchased
        }
    }
    var title: String { tab.title }
    var systemImage: String { tab.systemImage }
}

extension LibraryOrigin {
    static let dizzylab = Self(rawValue: "dizzylab", label: "DizzyLab", systemImage: "bag")
}
