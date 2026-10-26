import Foundation

extension ModuleID { static let netease = ModuleID(rawValue: "netease") }
nonisolated enum NeteaseRoute: Hashable {
    case album(Int), playlist(Int), daily, radio, charts, myPlaylists
    case recommended, quality, category(String), newAlbums(NeteaseRegion), newSongs(NeteaseRegion), personalizedSongs
    case artists, artist(Int), artistAlbums(Int), liked, recent, subscribedAlbums
    /// 搜索「查看全部」：关键词与结果类型（1 歌曲、10 专辑、100 歌手、1000 歌单）。
    case search(String, Int)
    var title: String {
        switch self {
        case .album: "专辑"
        case .playlist: "歌单"
        case .daily: "每日推荐"
        case .radio: "私人 FM"
        case .charts: "排行榜"
        case .myPlaylists: "我的歌单"
        case .recommended: "推荐歌单"
        case .quality: "精品歌单"
        case .category(let name): name == "全部" ? "分类歌单" : name
        case .newAlbums: "新碟上架"
        case .newSongs: "新歌速递"
        case .personalizedSongs: "新歌推荐"
        case .artists: "热门歌手"
        case .artist: "歌手"
        case .artistAlbums: "歌手专辑"
        case .liked: "我喜欢的音乐"
        case .recent: "最近播放"
        case .subscribedAlbums: "收藏专辑"
        case .search: "搜索"
        }
    }
    var requiresLogin: Bool {
        switch self { case .daily, .radio, .myPlaylists, .liked, .recent, .subscribedAlbums: true; default: false }
    }
    var isSongCollection: Bool {
        switch self { case .album, .playlist, .daily, .radio, .newSongs, .personalizedSongs, .artist, .liked, .recent: true; default: false }
    }
    var respondsToLibraryChanges: Bool {
        switch self { case .myPlaylists, .liked, .subscribedAlbums, .playlist: true; default: false }
    }
}
extension AppRoute {
    static func netease(_ route: NeteaseRoute) -> Self { Self(moduleID: .netease, destination: route, title: route.title) }
}

extension LibraryOrigin {
    static let netease = Self(rawValue: "netease", label: "网易云", systemImage: "cloud")
}
