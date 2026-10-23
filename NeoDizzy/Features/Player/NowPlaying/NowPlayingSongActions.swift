// Direct source port from MeloX (GPL-3.0), b8bc60f.
// NeoDizzy adapters are limited to track data, available playback features and localization.
import SwiftUI
import UIKit

/// 曲目的「…」菜单：前往专辑、查看歌手或社团。
struct NowPlayingSongActions: View {
    @Environment(ModuleRegistry.self) private var modules: ModuleRegistry?
    @Environment(OfflineLibraryStore.self) private var library
    @Environment(PlayerStore.self) private var player
    @Environment(\.openRoute) private var openRoute

    @State private var showsPlaylist = false
    let track: Track
    var onImportLyrics: (() -> Void)? = nil

    var body: some View {
        if let actions = modules?.songActions(for: track, onImportLyrics: onImportLyrics) {
            actions
        } else {
            HStack(spacing: 10) {
                FavoriteButton(track: track, playerStyle: true)
                NowPlayingMenuButton {
                    var items: [UIMenuElement] = [
                        UIAction(title: "加入歌单", image: UIImage(systemName: "text.badge.plus")) { _ in showsPlaylist = true }
                    ] + menuItems()
                    if let onImportLyrics {
                        items.append(UIAction(title: "导入本地歌词", image: UIImage(systemName: "square.and.arrow.down")) { _ in onImportLyrics() })
                    }
                    return items
                }.frame(width: 44, height: 44)
            }
            .songPlaylistSheet(isPresented: $showsPlaylist, track: track)
        }
    }

    private func menuItems() -> [UIMenuElement] {
        if let source = track.localSource {
            let artists = LibraryArtistNames.split(track.artists).map { (name: $0, route: AppRoute.libraryArtist($0, filter: .all)) }
            return [UIAction(title: String(localized: "前往专辑「\(track.albumTitle)」"), image: UIImage(systemName: "music.note.list")) { _ in
                openRoute(.localAlbum(id: library.localAlbum(for: track)?.id ?? source.albumID))
            }] + ArtistMenu.elements(artists) { openRoute($0) }
        }
        return []
    }
}

/// 「查看歌手」菜单项：只有一位时直接打开，多位时展开子菜单再选。
enum ArtistMenu {
    @MainActor
    static func elements(_ artists: [(name: String, route: AppRoute)], title: String = String(localized: "查看歌手"),
                         open: @escaping (AppRoute) -> Void) -> [UIMenuElement] {
        switch artists.count {
        case 0: return []
        case 1:
            let artist = artists[0]
            return [UIAction(title: "\(title)「\(artist.name)」", image: UIImage(systemName: "person")) { _ in open(artist.route) }]
        default:
            return [UIMenu(title: title, image: UIImage(systemName: "person.2"), children: artists.map { artist in
                UIAction(title: artist.name, image: UIImage(systemName: "person")) { _ in open(artist.route) }
            })]
        }
    }
}

/// 由 UIKit 负责按下、滑动、松开整个过程：播放器每秒刷新 SwiftUI，用 SwiftUI 的 Menu 会在手指还按着时被打断。
struct NowPlayingMenuButton: UIViewRepresentable {
    var items: () -> [UIMenuElement]

    final class Coordinator {
        var items: () -> [UIMenuElement]
        init(items: @escaping () -> [UIMenuElement]) { self.items = items }
    }

    func makeCoordinator() -> Coordinator { Coordinator(items: items) }

    func makeUIView(context: Context) -> UIButton {
        let button = UIButton(type: .system)
        button.setImage(
            UIImage(systemName: "ellipsis", withConfiguration: UIImage.SymbolConfiguration(pointSize: 20, weight: .semibold)),
            for: .normal
        )
        button.tintColor = .white
        button.backgroundColor = UIColor.white.withAlphaComponent(0.15)
        button.layer.cornerRadius = 22
        button.showsMenuAsPrimaryAction = true
        button.accessibilityLabel = String(localized: "更多")
        // 每次打开时再取当前的菜单项，而不是在 updateUIView 里换掉菜单打断正在进行的操作。
        button.menu = UIMenu(children: [UIDeferredMenuElement.uncached { [weak coordinator = context.coordinator] completion in
            completion(coordinator?.items() ?? [])
        }])
        return button
    }

    func updateUIView(_ button: UIButton, context: Context) {
        context.coordinator.items = items
    }
}
