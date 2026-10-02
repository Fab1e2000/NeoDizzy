import SwiftUI
import UniformTypeIdentifiers

struct NowPlayingLyricsPage: View {
    let track: Track
    let playerFrame: CGRect
    let controlsHeight: CGFloat
    let isActive: Bool
    @Binding var isInterfaceHidden: Bool
    let onArtworkFrameChange: (CGRect) -> Void
    @Environment(PlayerStore.self) private var player
    @Environment(OfflineLibraryStore.self) private var library
    @State private var lyrics: LocalLyrics?
    @State private var issue: String?
    @State private var importing = false
    @State private var importTrackID: String?
    @State private var revision = 0

    private var request: Request { Request(trackID: track.id, libraryRevision: library.contentRevision, revision: revision) }
    private struct Request: Hashable {
        let trackID: String
        let libraryRevision: Int
        let revision: Int
    }

    var body: some View {
        VStack(spacing: 16) {
            NowPlayingSongHeader(track: track, onArtworkFrameChange: onArtworkFrameChange, onImportLyrics: {
                importTrackID = track.id
                importing = true
            })
            if let issue {
                ContentUnavailableView {
                    Label("歌词读取失败", systemImage: "exclamationmark.bubble")
                } description: { Text(issue) } actions: {
                    Button("重试") { revision += 1 }
                }
                .padding(.bottom, controlsHeight)
            } else if let lyrics {
                if lyrics.isEmpty {
                    ContentUnavailableView("暂无本地歌词", systemImage: "quote.bubble",
                        description: Text("读取音频内嵌歌词或同目录的同名 LRC，也可为当前曲目导入歌词。不会联网搜索。"))
                    .padding(.bottom, controlsHeight)
                } else if lyrics.isTimed {
                    AppleMusicLocalLyricsView(lyrics: lyrics, playerFrame: playerFrame, activeID: lyrics.activeLine(at: player.progress),
                        bottomOverlayHeight: controlsHeight, isActive: isActive,
                        isInterfaceHidden: $isInterfaceHidden, onSeek: { player.seek(to: $0) })
                } else {
                    ScrollView {
                        Text(lyrics.plainText).font(.system(size: 36, weight: .bold)).lineSpacing(14)
                            .frame(maxWidth: .infinity, alignment: .leading).textSelection(.enabled)
                    }
                    .padding(.bottom, controlsHeight)
                }
            } else {
                ProgressView("读取本地歌词").frame(maxWidth: .infinity, maxHeight: .infinity)
                    .padding(.bottom, controlsHeight)
            }
        }
        .padding(.bottom, 12)
        .task(id: request) {
            lyrics = nil
            issue = nil
            isInterfaceHidden = false
            let requestedID = track.id
            let access = library.access(for: track)
            let url = library.localFile(for: track)
            do {
                let result = try await LocalLyricsReader.shared.load(trackID: requestedID, audioURL: url, access: access)
                try Task.checkCancellation()
                lyrics = result
            } catch is CancellationError { } catch {
                if !Task.isCancelled { issue = error.localizedDescription }
            }
        }
        .fileImporter(isPresented: $importing, allowedContentTypes: [.data, .plainText]) { result in
            guard let target = importTrackID else { return }
            switch result {
            case .success(let url):
                Task {
                    do {
                        try await LocalLyricsReader.shared.importFile(url, trackID: target)
                        if track.id == target { revision += 1 }
                    } catch { if track.id == target { issue = error.localizedDescription } }
                }
            case .failure(let error): issue = error.localizedDescription
            }
        }
    }

}
