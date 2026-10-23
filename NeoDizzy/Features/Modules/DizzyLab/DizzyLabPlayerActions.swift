import SwiftUI
import UIKit

struct DizzyLabPlayerActions: View {
    let track: Track
    let onImportLyrics: (() -> Void)?
    @Environment(OfflineLibraryStore.self) private var library
    @Environment(PlayerStore.self) private var player
    @Environment(\.openRoute) private var openRoute
    @State private var showsPlaylist = false
    var body: some View {
        HStack(spacing: 10) {
            FavoriteButton(track: track, playerStyle: true)
            NowPlayingMenuButton {
                var items: [UIMenuElement] = [UIAction(title: "加入歌单", image: UIImage(systemName: "text.badge.plus")) { _ in showsPlaylist = true }] + menuItems()
                if let onImportLyrics {
                    items.append(UIAction(title: "导入本地歌词", image: UIImage(systemName: "square.and.arrow.down")) { _ in onImportLyrics() })
                }
                return items
            }.frame(width: 44, height: 44)
        }.songPlaylistSheet(isPresented: $showsPlaylist, track: track)
    }
    private func menuItems() -> [UIMenuElement] {
        let discID = track.discID
        let downloadedLabel = library.collection(provider: "dizzylab", kind: "album", id: discID)?.detail.summary.labelName
        var items: [UIMenuElement] = [
            UIAction(title: String(localized: "前往专辑「\(track.albumTitle)」"), image: UIImage(systemName: "music.note.list")) { _ in
                openRoute(.disc(id: discID))
            },
            // DizzyLab 的「歌手」是发行专辑的社团；没下载过的专辑打开菜单时再查一次。
            UIDeferredMenuElement.uncached { [openRoute] completion in
                Task { @MainActor in
                    var label = downloadedLabel
                    if label == nil { label = try? await DizzyAPI.shared.discDetail(id: discID).summary.labelName }
                    let artists = label.map { [(name: $0, route: AppRoute.label(name: $0))] } ?? []
                    completion(ArtistMenu.elements(artists, title: "查看社团") { openRoute($0) })
                }
            },
        ]
        if player.isPreview {
            items.append(UIAction(title: String(localized: "前往专辑购买"), image: UIImage(systemName: "cart")) { _ in
                openRoute(.disc(id: discID))
            })
        }
        return items
    }
}
