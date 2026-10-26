import SwiftUI

struct QQMusicPlayerActions: View {
    let track: Track
    var onImportLyrics: (() -> Void)?
    @Environment(QQMusicStore.self) private var store
    @Environment(DownloadStore.self) private var downloads
    @State private var showsDownloads = false
    @State private var albumNavigation = AlbumNavigationPreparation()
    @Environment(\.openRoute) private var openRoute

    var body: some View {
        NowPlayingMenuButton(track: track) {
            var items: [UIMenuElement] = []
            items.append(UIAction(title: "下载歌曲", image: UIImage(systemName: "arrow.down.circle")) { _ in
                guard store.credential != nil else { store.showsAccount = true; return }
                Task {
                    await downloads.enqueueQQMusicSong(track, quality: store.playbackSettings.quality)
                    showsDownloads = true
                }
            })
            if !track.discID.isEmpty {
                items.append(UIAction(title: "前往专辑", image: UIImage(systemName: "square.stack")) { _ in
                    guard store.active else { return }
                    if let route = albumNavigation.begin(.qqmusic(.album(track.discID)), artworkURL: QQMusicSong.cover(albumMid: track.discID)) {
                        openRoute(route)
                    }
                })
            }
            if let onImportLyrics {
                items.append(UIAction(title: "导入本地歌词", image: UIImage(systemName: "square.and.arrow.down")) { _ in onImportLyrics() })
            }
            return items
        }.frame(width: 44, height: 44)
        .sheet(isPresented: $showsDownloads) { DownloadQueueSheet() }
        .preparedAlbumNavigation(albumNavigation)
        .onChange(of: track.id) { _, _ in albumNavigation.cancel() }
        .onChange(of: store.revision) { _, _ in albumNavigation.cancel() }
    }
}
