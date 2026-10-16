import Foundation

extension ModuleID {
    static let localLibrary = ModuleID(rawValue: "localLibrary")
}

/// 资料库里一项内容的来源。本地文件（包括下载好的）都算本地。
enum LibraryOrigin: String, CaseIterable, Hashable, Sendable {
    case local, netease, dizzylab

    init?(providerID: String) { self.init(rawValue: providerID) }

    var label: String {
        switch self {
        case .local: String(localized: "本地")
        case .netease: String(localized: "网易云")
        case .dizzylab: "DizzyLab"
        }
    }

    /// 封面右下角的来源图标。
    var systemImage: String {
        switch self {
        case .local: "iphone"
        case .netease: "cloud"
        case .dizzylab: "bag"
        }
    }
}

/// 资料库顶部的来源筛选。
enum LibraryOriginFilter: Hashable, Sendable {
    case all, only(LibraryOrigin)

    static var choices: [Self] { [.all] + LibraryOrigin.allCases.map(Self.only) }

    var label: String {
        switch self {
        case .all: String(localized: "全部")
        case .only(let origin): origin.label
        }
    }

    func includes(_ origin: LibraryOrigin) -> Bool {
        switch self {
        case .all: true
        case .only(let only): only == origin
        }
    }
}

enum LocalLibraryRoute: Hashable {
    case favorites
    case album(String), playlist(String)
    case albums(LibraryOriginFilter), playlists(LibraryOriginFilter), songs(LibraryOriginFilter)
    case artists(LibraryOriginFilter), artist(String, LibraryOriginFilter)
    case search(String)
}

extension AppRoute {
    static var favorites: Self { Self(moduleID: .localLibrary, destination: LocalLibraryRoute.favorites, title: "喜欢") }
    static func localPlaylist(id: String) -> Self {
        Self(moduleID: .localLibrary, destination: LocalLibraryRoute.playlist(id), title: String(localized: "本地歌单"))
    }

    static func libraryAlbums(_ filter: LibraryOriginFilter) -> Self {
        Self(moduleID: .localLibrary, destination: LocalLibraryRoute.albums(filter), title: String(localized: "专辑"))
    }
    static func libraryPlaylists(_ filter: LibraryOriginFilter) -> Self {
        Self(moduleID: .localLibrary, destination: LocalLibraryRoute.playlists(filter), title: String(localized: "歌单"))
    }
    static func librarySongs(_ filter: LibraryOriginFilter) -> Self {
        Self(moduleID: .localLibrary, destination: LocalLibraryRoute.songs(filter), title: String(localized: "歌曲"))
    }
    static func libraryArtists(_ filter: LibraryOriginFilter) -> Self {
        Self(moduleID: .localLibrary, destination: LocalLibraryRoute.artists(filter), title: String(localized: "歌手"))
    }
    static func libraryArtist(_ name: String, filter: LibraryOriginFilter) -> Self {
        Self(moduleID: .localLibrary, destination: LocalLibraryRoute.artist(name, filter), title: name)
    }

    static func librarySearch(_ query: String) -> Self {
        Self(moduleID: .localLibrary, destination: LocalLibraryRoute.search(query), title: String(localized: "搜索"))
    }

    static func localAlbum(id: String) -> Self {
        Self(moduleID: .localLibrary, destination: LocalLibraryRoute.album(id), title: String(localized: "本地专辑"))
    }
}
