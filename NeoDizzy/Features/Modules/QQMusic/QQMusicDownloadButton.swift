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
        Button {
            Task {
                await downloads.enqueueQQMusic(kind: kind, id: id, title: title, coverURL: coverURL, quality: store.playbackSettings.quality)
                showsQueue = true
            }
        } label: {
            Image(systemName: "arrow.down")
                .font(.title2.weight(.semibold))
                .frame(width: 30, height: 30)
        }
        .accessibilityLabel("下载")
        .sheet(isPresented: $showsQueue) { DownloadQueueSheet() }
    }
}
#endif
