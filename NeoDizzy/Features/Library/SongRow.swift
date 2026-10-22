import SwiftUI

// Adapted from MeloX Features/Song/TrackRowView.swift and Features/Playlist/PlaylistTrackList.swift (GPL-3.0).

/// 歌曲行的附加操作，同时出现在行尾「⋯」菜单和长按菜单里。
struct SongRowAction: Identifiable {
    let id: String
    let title: String
    let systemImage: String
    var role: ButtonRole?
    var disabled = false
    let perform: () -> Void
}

/// 所有歌曲列表共用的一行，两种样式：
/// - 序号式：专辑里用，沿用 MeloX 专辑列表：序号 + 最多两行歌名，每行 66pt，
///   当前播放的序号换成圆圈播放按钮、整行浅灰底；
/// - 封面式：其他列表用，44pt 封面 + 歌名 + 「歌手 · 专辑」，最少 60pt 高，
///   当前播放的歌名用主题色、封面上叠播放状态。
/// 列表里都不画分隔线。
///
/// 行本身不留左右边距，由外层容器统一留；点当前播放的歌是暂停、继续。
struct SongRow: View {
    enum Style {
        case numbered(String)
        case artwork
    }

    let track: Track
    var style: Style = .artwork
    var origin: LibraryOrigin?
    var isDownloaded = false
    var isPreview = false
    var editTags: (() -> Void)?
    var actions: [SongRowAction] = []
    let play: () -> Void
    @State private var songActions = SongActionPresentation()
    @Environment(PlayerStore.self) private var player

    private var isCurrent: Bool { player.currentTrack?.id == track.id }

    private var isNumbered: Bool {
        if case .numbered = style { return true }
        return false
    }

    var body: some View {
        HStack(spacing: isNumbered ? 4 : 8) {
            Button(action: primaryAction) {
                HStack(spacing: 8) {
                    HStack(spacing: 12) {
                        leading.frame(width: isNumbered ? 40 : 44)
                        titles.frame(maxWidth: .infinity, alignment: .leading)
                    }
                    badges
                }
                .contentShape(.rect)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("\(track.title)，\(track.artists)")
            .accessibilityValue(isCurrent ? "当前播放" : "")

            Menu { menuItems } label: {
                Image(systemName: "ellipsis")
                    .font(.body.weight(.semibold))
                    .foregroundStyle(DizzyPalette.text)
                    .frame(width: isNumbered ? 42 : 36, height: 44)
                    .contentShape(.rect)
            }
            .accessibilityLabel("\(track.title)的更多操作")
        }
        // 序号式与 MeloX 相同：44pt 的更多按钮上下各留 11pt，按钮离屏幕右缘 8pt。
        .padding(.vertical, isNumbered ? 11 : 8)
        .padding(.trailing, isNumbered ? -12 : 0)
        .frame(minHeight: isNumbered ? 66 : 60)
        .background {
            // 当前播放的浅灰底铺满整个屏幕宽度。
            if isNumbered && isCurrent {
                Color.primary.opacity(0.10).padding(.horizontal, -20)
            }
        }
        .contentShape(.rect)
        .contextMenu { menuItems }
        .modifier(SongActionPresentationModifier(track: track, presentation: songActions))
    }

    /// 已下载优先：正常情况下下载完成会删掉缓存，两者不会同时出现。
    private var cachedQuality: String? { isDownloaded ? nil : player.cachedQuality(for: track) }

    @ViewBuilder private var badges: some View {
        if isNumbered {
            if isPreview {
                Text("试听").font(.caption2).foregroundStyle(.secondary)
            }
        } else if isPreview {
            Text("试听")
                .font(.caption2.weight(.semibold))
                .foregroundStyle(DizzyPalette.mutedText)
                .padding(.horizontal, 6)
                .overlay { RoundedRectangle(cornerRadius: 4).strokeBorder(Color(uiColor: .separator), lineWidth: 1) }
        }
        // 实心是已下载，空心是已缓存（可能被系统清掉），未下载不显示。
        if isDownloaded || cachedQuality != nil {
            Image(systemName: isDownloaded ? "arrow.down.circle.fill" : "arrow.down.circle")
                .font(isNumbered ? .caption : .footnote)
                .foregroundStyle(DizzyPalette.mutedText)
                .accessibilityLabel(isDownloaded ? "已下载" : "已缓存")
        }
    }

    @ViewBuilder private var leading: some View {
        switch style {
        case .numbered(let number):
            if isCurrent {
                ZStack {
                    Circle().stroke(Color.primary.opacity(0.60), lineWidth: 1.5)
                    if player.isLoading {
                        ProgressView().controlSize(.mini)
                    } else {
                        Image(systemName: player.isPlaying ? "pause.fill" : "play.fill")
                            .font(.caption.weight(.bold))
                    }
                }
                .frame(width: 32, height: 32)
            } else {
                Text(number)
                    .font(.title3)
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }
        case .artwork:
            ArtworkImage(url: track.coverURL, cornerRadius: 6)
                .frame(width: 44, height: 44)
                .overlay {
                    if isCurrent {
                        RoundedRectangle(cornerRadius: 6).fill(.black.opacity(0.38))
                        playbackIndicator(color: .white)
                    }
                }
                .accessibilityHidden(true)
        }
    }

    @ViewBuilder private func playbackIndicator(color: Color) -> some View {
        if player.isLoading {
            ProgressView().controlSize(.mini).tint(color)
        } else {
            Image(systemName: "waveform")
                .font(.subheadline.weight(.bold))
                .foregroundStyle(color)
                .symbolEffect(.variableColor.iterative, isActive: player.isPlaying)
                .accessibilityHidden(true)
        }
    }

    @ViewBuilder private var titles: some View {
        switch style {
        case .numbered:
            Text(track.title)
                .font(.body)
                .foregroundStyle(DizzyPalette.text)
                .lineLimit(2)
                .multilineTextAlignment(.leading)
        case .artwork:
            let title = Text(track.title)
                .font(.body)
                .foregroundStyle(isCurrent ? DizzyPalette.accent : DizzyPalette.text)
                .lineLimit(1)
            VStack(alignment: .leading, spacing: 2) {
                title
                if origin != nil || !subtitle.isEmpty {
                    HStack(spacing: 6) {
                        if let origin { LibraryOriginBadge(origin: origin) }
                        Text(subtitle)
                            .font(.footnote)
                            .foregroundStyle(DizzyPalette.mutedText)
                            .lineLimit(1)
                    }
                }
            }
        }
    }

    private var subtitle: String {
        [track.artists, track.albumTitle].filter { !$0.isEmpty }.joined(separator: " · ")
    }

    @ViewBuilder private var menuItems: some View {
        let pauses = isCurrent && player.isPlaying
        Button(pauses ? "暂停" : "播放", systemImage: pauses ? "pause.fill" : "play.fill", action: primaryAction)
        SongLibraryActions(track: track, presentation: songActions)
        if let editTags {
            Button("编辑音乐标签", systemImage: "pencil", action: editTags)
        }
        ForEach(actions) { action in
            Button(action.title, systemImage: action.systemImage, role: action.role, action: action.perform)
                .disabled(action.disabled)
        }
    }

    private func primaryAction() {
        if isCurrent { player.togglePlayback() } else { play() }
    }
}

/// 加载中的歌曲行，尺寸与 `SongRow` 一致。
struct SongRowPlaceholder: View {
    var numbered = false

    var body: some View {
        HStack(spacing: numbered ? 4 : 8) {
            HStack(spacing: 12) {
                RoundedRectangle(cornerRadius: numbered ? 3 : 6)
                    .fill(.gray.opacity(0.18))
                    .frame(width: numbered ? 18 : 44, height: numbered ? 18 : 44)
                    .frame(width: numbered ? 40 : 44)
                VStack(alignment: .leading, spacing: 2) {
                    Text("歌曲名称正在载入").font(.body)
                    if !numbered { Text("歌手 · 专辑").font(.footnote) }
                }
                .redacted(reason: .placeholder)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            Capsule().fill(.gray.opacity(0.18)).frame(width: 18, height: 5)
                .frame(width: numbered ? 42 : 36, height: 44)
        }
        .padding(.vertical, numbered ? 11 : 8)
        .padding(.trailing, numbered ? -12 : 0)
        .frame(minHeight: numbered ? 66 : 60)
    }
}

extension View {
    /// 放进 `List` 的歌曲、专辑行：去掉系统分隔线和上下留白，左右与页面边距对齐。
    func songListRow() -> some View {
        listRowInsets(EdgeInsets(top: 0, leading: 20, bottom: 0, trailing: 20))
            .listRowSeparator(.hidden)
    }
}
