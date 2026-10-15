#if os(iOS)
import SwiftUI

struct DownloadQueueSheet: View {
    @Environment(DownloadStore.self) private var downloads
    @Environment(\.dismiss) private var dismiss
    var body: some View {
        NavigationStack {
            ScrollView { DownloadQueueSection(jobs: downloads.jobs).padding(20) }
                .dizzyPageBackground()
                .navigationTitle("下载")
                .toolbar { ToolbarItem(placement: .cancellationAction) { Button("完成") { dismiss() } } }
        }
    }
}

struct NeteaseDownloadButton: View {
    let kind: String
    let id: Int
    let title: String
    let coverURL: URL?
    @Environment(NeteaseStore.self) private var store
    @Environment(DownloadStore.self) private var downloads
    @State private var showsQueue = false
    var body: some View {
        Button("下载", systemImage: "arrow.down.circle") {
            Task {
                await downloads.enqueueNetease(kind: kind, id: id, title: title, coverURL: coverURL, quality: store.playbackSettings.download)
                showsQueue = true
            }
        }
        .sheet(isPresented: $showsQueue) { DownloadQueueSheet() }
    }
}

#endif
