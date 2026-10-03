import SwiftUI
import UniformTypeIdentifiers

/// 右侧面板：歌词与待播清单，与 Music 的检查器面板相同。
struct PlayerInspector: View {
    @Environment(MacAppModel.self) private var model

    var body: some View {
        VStack(spacing: 0) {
            Picker("面板", selection: Binding(get: { model.playerPanel ?? .lyrics }, set: { model.playerPanel = $0 })) {
                Text("歌词").tag(PlayerPanel.lyrics)
                Text("待播清单").tag(PlayerPanel.queue)
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            switch model.playerPanel ?? .lyrics {
            case .lyrics: LyricsPanel()
            case .queue: QueuePanel()
            }
        }
        // 面板宽度只由检查器列决定；歌词行的理想宽度随内容变化，不能反过来影响列宽。
        .frame(minWidth: 0, idealWidth: 0, maxWidth: .infinity, maxHeight: .infinity)
    }
}

/// 本地歌词：手动导入 → 同目录 LRC → 内嵌歌词，与 iOS 的歌词页相同，不联网。
struct LyricsPanel: View {
    var fontSize: CGFloat = 22
    var tone: PlayerControlTone = .standard
    @Environment(PlayerStore.self) private var player
    @Environment(OfflineLibraryStore.self) private var library
    @State private var lyrics: LocalLyrics?
    @State private var issue: String?
    @State private var revision = 0
    @State private var isInterfaceHidden = false

    private struct Request: Hashable {
        let trackID: String
        let libraryRevision: Int
        let revision: Int
    }

    var body: some View {
        Group {
            if let track = player.currentTrack {
                content(track)
                    .task(id: Request(trackID: track.id, libraryRevision: library.contentRevision, revision: revision)) {
                        await load(track)
                    }
            } else {
                PanelPlaceholder(title: "没有正在播放的歌曲", systemImage: "quote.bubble", tone: tone)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    @ViewBuilder private func content(_ track: Track) -> some View {
        if let issue {
            PanelPlaceholder(title: "歌词读取失败", systemImage: "exclamationmark.bubble", message: issue, tone: tone) {
                Button("重试") { revision += 1 }
            }
        } else if let lyrics {
            if lyrics.isEmpty {
                PanelPlaceholder(title: "暂无本地歌词", systemImage: "quote.bubble",
                                 message: "读取音频内嵌歌词或同目录的同名 LRC，也可为当前曲目导入歌词。不会联网搜索。", tone: tone) {
                    importButton(track)
                }
            } else {
                VStack(spacing: 0) {
                    if lyrics.isTimed {
                        GeometryReader { proxy in
                            AppleMusicLocalLyricsView(lyrics: lyrics, playerFrame: proxy.frame(in: .global),
                                                      activeID: lyrics.activeLine(at: player.progress),
                                                      bottomOverlayHeight: 0, isActive: true,
                                                      isInterfaceHidden: $isInterfaceHidden,
                                                      onSeek: { player.seek(to: $0) },
                                                      fixedFontSize: fontSize, foreground: tone.primary)
                        }
                        .padding(.horizontal, 18)
                    } else {
                        ScrollView {
                            Text(lyrics.plainText)
                                .font(.system(size: fontSize, weight: .bold))
                                .lineSpacing(fontSize * 0.35)
                                .foregroundStyle(tone.primary)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .textSelection(.enabled)
                                .padding(18)
                        }
                    }
                    HStack {
                        if !lyrics.source.isEmpty {
                            Text(lyrics.source).font(.caption).foregroundStyle(tone.secondary)
                        }
                        Spacer()
                        importButton(track).controlSize(.small)
                    }
                    .padding(.horizontal, 14)
                    .padding(.vertical, 8)
                }
            }
        } else {
            ProgressView("读取本地歌词").frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    private func importButton(_ track: Track) -> some View {
        Button("导入歌词…") {
            let trackID = track.id
            Task {
                guard let url = await FolderPanel.chooseFile(message: String(localized: "选择 LRC 或 TXT 歌词文件，只会复制到 App 内，不改动音乐文件。"),
                                                             types: [.data, .plainText]) else { return }
                do {
                    try await LocalLyricsReader.shared.importFile(url, trackID: trackID)
                    if player.currentTrack?.id == trackID { revision += 1 }
                } catch {
                    if player.currentTrack?.id == trackID { issue = error.localizedDescription }
                }
            }
        }
    }

    private func load(_ track: Track) async {
        lyrics = nil
        issue = nil
        do {
            let result = try await LocalLyricsReader.shared.load(trackID: track.id, audioURL: library.localFile(for: track),
                                                                 access: library.access(for: track))
            try Task.checkCancellation()
            lyrics = result
        } catch is CancellationError {
        } catch {
            if !Task.isCancelled { issue = error.localizedDescription }
        }
    }
}

/// 待播清单：当前曲目、随机与循环开关、接下来要播放的曲目，双击直接播放。
struct QueuePanel: View {
    @Environment(PlayerStore.self) private var player

    var body: some View {
        if let current = player.currentTrack {
            List {
                Section("正在播放") {
                    QueueRow(track: current, isCurrent: true)
                }
                Section {
                    let upcoming = player.upcoming
                    if upcoming.isEmpty {
                        Text(player.isDiscovery ? "随便听听：下一首获取新曲目，上一首返回收听历史。"
                             : player.repeatMode == .one ? "正在单曲循环" : "后面没有要播放的曲目了")
                            .foregroundStyle(.secondary)
                    } else {
                        ForEach(upcoming) { entry in
                            QueueRow(track: entry.track)
                                .onTapGesture(count: 2) { player.playFromQueue(at: entry.index) }
                                .contextMenu {
                                    Button("播放", systemImage: "play") { player.playFromQueue(at: entry.index) }
                                }
                        }
                    }
                } header: {
                    HStack {
                        Text("待播清单")
                        Spacer()
                        if !player.isDiscovery {
                            Toggle(isOn: Binding(get: { player.isShuffled }, set: { if $0 != player.isShuffled { player.toggleShuffle() } })) {
                                Image(systemName: "shuffle")
                            }
                            .toggleStyle(.button)
                            .help("随机播放")
                            Button { player.cycleRepeatMode() } label: { Image(systemName: player.repeatMode.systemImage) }
                                .foregroundStyle(player.repeatMode == .off ? Color.secondary : Color.dizzyGold)
                                .help(player.repeatMode.accessibilityTitle)
                        }
                    }
                    .buttonStyle(.borderless)
                    .controlSize(.small)
                }
            }
            .listStyle(.inset)
            .scrollContentBackground(.hidden)
        } else {
            PanelPlaceholder(title: "待播清单为空", systemImage: "list.bullet", message: "播放专辑后，接下来的曲目会显示在这里。")
        }
    }
}

private struct QueueRow: View {
    let track: Track
    var isCurrent = false

    var body: some View {
        HStack(spacing: 10) {
            ArtworkImage(url: track.coverURL, cornerRadius: 4)
                .frame(width: 36, height: 36)
            VStack(alignment: .leading, spacing: 1) {
                Text(track.title).lineLimit(1)
                    .foregroundStyle(isCurrent ? Color.dizzyGold : .primary)
                Text(track.artists).font(.callout).foregroundStyle(.secondary).lineLimit(1)
            }
            Spacer(minLength: 4)
            if let duration = track.duration {
                Text(TimeFormat.clock(duration)).font(.callout.monospacedDigit()).foregroundStyle(.secondary)
            }
        }
        .contentShape(.rect)
    }
}

/// 面板里的空状态。文字随面板宽度换行，不会把检查器撑宽。
private struct PanelPlaceholder<Actions: View>: View {
    let title: LocalizedStringKey
    let systemImage: String
    var message: String?
    var tone: PlayerControlTone = .standard
    @ViewBuilder var actions: Actions

    var body: some View {
        VStack(spacing: 10) {
            Image(systemName: systemImage)
                .font(.system(size: 34))
                .foregroundStyle(tone.secondary)
            Text(title).font(.headline).foregroundStyle(tone.primary)
            if let message {
                Text(message)
                    .foregroundStyle(tone.secondary)
                    .multilineTextAlignment(.center)
            }
            actions
        }
        .padding(24)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

extension PanelPlaceholder where Actions == EmptyView {
    init(title: LocalizedStringKey, systemImage: String, message: String? = nil, tone: PlayerControlTone = .standard) {
        self.init(title: title, systemImage: systemImage, message: message, tone: tone, actions: { EmptyView() })
    }
}
