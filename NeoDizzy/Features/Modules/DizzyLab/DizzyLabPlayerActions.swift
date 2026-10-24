import Combine
import SwiftUI
import UIKit

struct DizzyLabPlayerActions: View {
    let track: Track
    let onImportLyrics: (() -> Void)?
    @Environment(OfflineLibraryStore.self) private var library
    @Environment(PlayerStore.self) private var player
    @Environment(DizzyLabContentCache.self) private var contentCache
    @Environment(\.openRoute) private var openRoute
    @State private var showsPlaylist = false
    @State private var albumNavigation = AlbumNavigationPreparation()
    var body: some View {
        HStack(spacing: 4.25) {
            FavoriteButton(track: track, playerStyle: true)
            NowPlayingMenuButton(track: track) {
                var items: [UIMenuElement] = [UIAction(title: "加入歌单", image: UIImage(systemName: "text.badge.plus")) { _ in showsPlaylist = true }] + menuItems()
                if let onImportLyrics {
                    items.append(UIAction(title: "导入本地歌词", image: UIImage(systemName: "square.and.arrow.down")) { _ in onImportLyrics() })
                }
                return items
            }.frame(width: 44, height: 44)
        }.songPlaylistSheet(isPresented: $showsPlaylist, track: track)
            .preparedAlbumNavigation(albumNavigation)
            .onChange(of: track.id) { albumNavigation.cancel() }
            .onReceive(NotificationCenter.default.publisher(for: .dizzyAccountDidChange)) { _ in albumNavigation.cancel() }
    }
    private func menuItems() -> [UIMenuElement] {
        var items: [UIMenuElement] = [
            UIAction(title: String(localized: "前往专辑「\(track.albumTitle)」"), image: UIImage(systemName: "music.note.list")) { _ in
                openAlbum()
            },
        ]
        if player.isPreview {
            items.append(UIAction(title: String(localized: "前往专辑购买"), image: UIImage(systemName: "cart")) { _ in
                openAlbum()
            })
        }
        return items
    }

    private func openAlbum() {
        let artwork = library.collection(provider: "dizzylab", kind: "album", id: track.discID)?.coverURL ?? track.coverURL
        contentCache.remember([DiscSummary(id: track.discID, title: track.albumTitle, coverURL: artwork)])
        if let route = albumNavigation.begin(.disc(id: track.discID), artworkURL: artwork) { openRoute(route) }
    }
}
