#if os(iOS)
import SwiftUI

struct QQMusicDownloadButton: View {
    let kind: String
    let id: String
    let title: String
    let coverURL: URL?
    @Environment(QQMusicStore.self) private var store
    @Environment(DownloadStore.self) private var downloads
    @State private var showsQueue = false

    var body: some View {
        Button("下载", systemImage: "arrow.down.circle") {
            Task {
                await downloads.enqueueQQMusic(kind: kind, id: id, title: title, coverURL: coverURL, quality: store.playbackSettings.quality)
                showsQueue = true
            }
        }
        .sheet(isPresented: $showsQueue) { DownloadQueueSheet() }
    }
}
#endif
