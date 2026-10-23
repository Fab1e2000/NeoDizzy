import SwiftUI

struct QQMusicPlayerActions: View {
    let track: Track
    var onImportLyrics: (() -> Void)?
    @Environment(QQMusicStore.self) private var store
    @Environment(DownloadStore.self) private var downloads
    @State private var singers: [QQMusicArtist] = []
    @State private var showsDownloads = false
    @Environment(\.openRoute) private var openRoute

    var body: some View {
        NowPlayingMenuButton {
            var items: [UIMenuElement] = []
            items.append(UIAction(title: "下载歌曲", image: UIImage(systemName: "arrow.down.circle")) { _ in
                guard store.credential != nil else { store.showsAccount = true; return }
                Task {
                    await downloads.enqueueQQMusicSong(track, quality: store.playbackSettings.quality)
                    showsDownloads = true
                }
            })
            for artist in singers {
                items.append(UIAction(title: "歌手 · \(artist.name)", image: UIImage(systemName: "person")) { _ in
                    openRoute(.qqmusic(.artist(artist.id)))
                })
            }
            if !track.discID.isEmpty {
                items.append(UIAction(title: "前往专辑", image: UIImage(systemName: "square.stack")) { _ in
                    openRoute(.qqmusic(.album(track.discID)))
                })
            }
            if let mid = track.remoteSource?.itemID {
                items.append(UIAction(title: "相似歌曲", image: UIImage(systemName: "sparkles")) { _ in
                    openRoute(.qqmusic(.similar(mid)))
                })
                items.append(UIAction(title: "歌曲详情", image: UIImage(systemName: "music.note")) { _ in
                    openRoute(.qqmusic(.song(mid)))
                })
            }
            if let onImportLyrics {
                items.append(UIAction(title: "导入本地歌词", image: UIImage(systemName: "square.and.arrow.down")) { _ in onImportLyrics() })
            }
            return items
        }.frame(width: 44, height: 44)
        .sheet(isPresented: $showsDownloads) { DownloadQueueSheet() }
        .task(id: "\(store.revision)/\(track.id)") {
            singers = []
            let revision = store.revision
            guard let mid = track.remoteSource?.itemID,
                  let song = try? await store.api.song(mid: mid), !Task.isCancelled,
                  store.active, store.revision == revision else { return }
            singers = song.singers
        }
    }
}
