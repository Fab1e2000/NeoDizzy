import Foundation

extension ModuleID {
    static let localLibrary = ModuleID(rawValue: "localLibrary")
}

enum LocalLibraryRoute: Hashable { case album(String) }

extension AppRoute {
    static func localAlbum(id: String) -> Self {
        Self(moduleID: .localLibrary, destination: LocalLibraryRoute.album(id), title: String(localized: "本地专辑"))
    }
}
