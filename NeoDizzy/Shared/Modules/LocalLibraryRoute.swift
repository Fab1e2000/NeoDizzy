import Foundation

extension ModuleID {
    static let localLibrary = ModuleID(rawValue: "localLibrary")
}

enum LocalLibraryRoute: Hashable { case album(String), playlist(String), albums, playlists, songs }

extension AppRoute {
    static func localPlaylist(id: String) -> Self {
        Self(moduleID: .localLibrary, destination: LocalLibraryRoute.playlist(id), title: String(localized: "本地歌单"))
    }

    static var localAlbums: Self { Self(moduleID: .localLibrary, destination: LocalLibraryRoute.albums, title: String(localized: "专辑")) }
    static var localPlaylists: Self { Self(moduleID: .localLibrary, destination: LocalLibraryRoute.playlists, title: String(localized: "歌单")) }
    static var localSongs: Self { Self(moduleID: .localLibrary, destination: LocalLibraryRoute.songs, title: String(localized: "歌曲")) }

    static func localAlbum(id: String) -> Self {
        Self(moduleID: .localLibrary, destination: LocalLibraryRoute.album(id), title: String(localized: "本地专辑"))
    }
}
