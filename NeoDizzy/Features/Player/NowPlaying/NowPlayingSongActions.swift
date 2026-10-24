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
    @State private var albumNavigation = AlbumNavigationPreparation()
    let track: Track
    var onImportLyrics: (() -> Void)? = nil

    var body: some View {
        if let actions = modules?.songActions(for: track, onImportLyrics: onImportLyrics) {
            actions
        } else {
            HStack(spacing: 4.25) {
                FavoriteButton(track: track, playerStyle: true)
                NowPlayingMenuButton(track: track) {
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
            .preparedAlbumNavigation(albumNavigation)
            .onChange(of: track.id) { albumNavigation.cancel() }
        }
    }

    private func menuItems() -> [UIMenuElement] {
        if let source = track.localSource {
            return [UIAction(title: String(localized: "前往专辑「\(track.albumTitle)」"), image: UIImage(systemName: "music.note.list")) { _ in
                let album = library.localAlbum(for: track)
                let destination = AppRoute.localAlbum(id: album?.id ?? source.albumID)
                if let route = albumNavigation.begin(destination, artworkURL: album?.coverURL) { openRoute(route) }
            }]
        }
        return []
    }
}

/// 由 UIKit 负责按下、滑动、松开整个过程：播放器每秒刷新 SwiftUI，用 SwiftUI 的 Menu 会在手指还按着时被打断。
struct NowPlayingMenuButton: UIViewRepresentable {
    var track: Track? = nil
    @Environment(ModuleRegistry.self) private var modules: ModuleRegistry?
    @Environment(\.openRoute) private var openRoute
    var items: () -> [UIMenuElement]

    final class Coordinator {
        var items: () -> [UIMenuElement]
        let artists = PlayerArtistMenuController()
        init(items: @escaping () -> [UIMenuElement]) { self.items = items }
    }

    func makeCoordinator() -> Coordinator { Coordinator(items: items) }

    func makeUIView(context: Context) -> UIButton {
        let button = UIButton(type: .system)
        button.setImage(
            UIImage(systemName: "ellipsis", withConfiguration: UIImage.SymbolConfiguration(pointSize: 18, weight: .semibold)),
            for: .normal
        )
        button.tintColor = .white
        button.backgroundColor = .clear
        button.layer.cornerRadius = 22
        button.showsMenuAsPrimaryAction = true
        button.accessibilityLabel = String(localized: "更多")
        // 每次打开时再取当前的菜单项，而不是在 updateUIView 里换掉菜单打断正在进行的操作。
        context.coordinator.artists.bind(track: track, modules: modules, open: { openRoute($0) })
        button.menu = UIMenu(children: [UIDeferredMenuElement.uncached { [weak coordinator = context.coordinator, weak button] completion in
            guard let coordinator else { completion([]); return }
            var items = coordinator.items()
            if let button, let action = coordinator.artists.action(for: button) { items.append(action) }
            completion(items)
        }])
        return button
    }

    func updateUIView(_ button: UIButton, context: Context) {
        context.coordinator.items = items
        if context.coordinator.artists.bind(track: track, modules: modules, open: { openRoute($0) }) {
            button.contextMenuInteraction?.dismissMenu()
        }
    }

    static func dismantleUIView(_ uiView: UIButton, coordinator: Coordinator) {
        coordinator.artists.cancel()
    }
}
