// Direct source port from MeloX (GPL-3.0), b8bc60f.
// NeoDizzy adapters are limited to track data, available playback features and localization.
import SwiftUI
import UIKit

/// 曲目的「…」菜单：前往专辑、在网页中打开。
struct NowPlayingSongActions: View {
    @Environment(ModuleRegistry.self) private var modules: ModuleRegistry?
    @Environment(OfflineLibraryStore.self) private var library
    @Environment(PlayerStore.self) private var player
    @Environment(\.openRoute) private var openRoute
    @Environment(\.openURL) private var openURL

    let track: Track
    var onImportLyrics: (() -> Void)? = nil

    var body: some View {
        if let actions = modules?.songActions(for: track, onImportLyrics: onImportLyrics) {
            actions
        } else {
            NowPlayingMenuButton {
                var items = menuItems()
                if let onImportLyrics {
                    items.append(UIAction(title: "导入本地歌词", image: UIImage(systemName: "square.and.arrow.down")) { _ in onImportLyrics() })
                }
                return items
            }.frame(width: 44, height: 44)
        }
    }

    private func menuItems() -> [UIMenuElement] {
        if let source = track.localSource {
            return [UIAction(title: String(localized: "前往专辑「\(track.albumTitle)」"), image: UIImage(systemName: "music.note.list")) { _ in
                openRoute(.localAlbum(id: library.localAlbum(for: track)?.id ?? source.albumID))
            }]
        }
        if let source = track.remoteSource {
            guard source.providerID == "netease" else { return [] }
            var items: [UIMenuElement] = []
            if let albumID = Int(track.discID), albumID > 0 {
                items.append(UIAction(title: "前往专辑", image: UIImage(systemName: "music.note.list")) { _ in openRoute(.netease(.album(albumID))) })
            }
            if let url = URL(string: "https://music.163.com/#/song?id=\(source.itemID)") {
                items.append(UIAction(title: "在网易云网页中打开", image: UIImage(systemName: "safari")) { _ in openURL(url) })
            }
            return items
        }
        let discID = track.discID
        var items: [UIMenuElement] = [
            UIAction(title: String(localized: "前往专辑「\(track.albumTitle)」"), image: UIImage(systemName: "music.note.list")) { _ in
                openRoute(.disc(id: discID))
            },
        ]
        if player.isPreview {
            items.append(UIAction(title: String(localized: "前往专辑购买"), image: UIImage(systemName: "cart")) { _ in
                openRoute(.disc(id: discID))
            })
        }
        items.append(UIAction(title: String(localized: "在网页中打开"), image: UIImage(systemName: "safari")) { _ in
            openURL(DizzyURL.disc(discID))
        })
        return items
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
