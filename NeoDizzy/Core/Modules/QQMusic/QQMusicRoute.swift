import Foundation

extension ModuleID { static let qqmusic = ModuleID(rawValue: "qqmusic") }

nonisolated enum QQMusicRoute: Hashable {
    case search(String), album(String), playlist(String), chart(String), song(String)
    case recommended, charts, chartGroup(String), radar, daily
    case typedSearch(String, QQMusicSearchKind), artist(String), artistAlbums(String), artists, newAlbums(Int), similar(String)

    var title: String {
        switch self {
        case .search, .typedSearch: "搜索"
        case .artist, .artists: "歌手"
        case .artistAlbums: "歌手专辑"
        case .newAlbums: "新碟上架"
        case .similar: "相似歌曲"
        case .album: "专辑"
        case .playlist: "歌单"
        case .chart: "排行榜"
        case .song: "歌曲"
        case .recommended: "推荐歌单"
        case .radar: "雷达推荐"
        case .daily: "每日30首"
        case .charts, .chartGroup: "排行榜"
        }
    }
}

extension AppRoute {
    static func qqmusic(_ route: QQMusicRoute) -> Self {
        Self(moduleID: .qqmusic, destination: route, title: route.title)
    }
}

extension LibraryOrigin {
    static let qqmusic = Self(rawValue: "qqmusic", label: "QQ 音乐", systemImage: "music.note")
}
