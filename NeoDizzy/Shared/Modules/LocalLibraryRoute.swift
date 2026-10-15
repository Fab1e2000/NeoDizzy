import Foundation

extension ModuleID {
    static let localLibrary = ModuleID(rawValue: "localLibrary")
}

enum LocalLibraryRoute: Hashable { case album(String), playlist(String) }

extension AppRoute {
    static func localPlaylist(id: String) -> Self {
        Self(moduleID: .localLibrary, destination: LocalLibraryRoute.playlist(id), title: String(localized: "本地歌单"))
    }

    static func localAlbum(id: String) -> Self {
        Self(moduleID: .localLibrary, destination: LocalLibraryRoute.album(id), title: String(localized: "本地专辑"))
    }
}
