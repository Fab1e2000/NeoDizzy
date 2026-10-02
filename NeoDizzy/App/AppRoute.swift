import Foundation

/// 各标签页导航栈里可以推入的页面。
///
/// DizzyLab 的专辑、pack 用字符串 ID（如 `KSEP-001`），社团在网址里用名字（`/l/<名字>`），
/// 用户用数字 ID（`/u/<id>`）。
enum AppRoute: Hashable {
    case disc(id: String)
    case localAlbum(id: String)
    case label(name: String)
    case user(id: Int)
    case tag(String)
    case pack(id: String)
    case review(id: Int)

    var title: String {
        switch self {
        case .localAlbum: String(localized: "本地专辑")
        case .disc: String(localized: "专辑")
        case .label(let name): name
        case .user: String(localized: "用户主页")
        case .tag(let tag): "#\(tag)"
        case .pack: String(localized: "合集")
        case .review: "repo 长评"
        }
    }
}
