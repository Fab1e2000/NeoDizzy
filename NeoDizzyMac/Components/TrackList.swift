import AppKit
import SwiftUI

/// 专辑曲目列表，交互与 Music 相同：悬停高亮，单击选中，双击或回车播放，
/// 正在播放的曲目显示扬声器图标，右键菜单提供更多操作。
struct TrackList<RowMenu: View>: View {
    let tracks: [Track]
    var isPreview: (Track) -> Bool = { _ in false }
    /// 与专辑艺术家不同的曲目才在右侧显示艺术家。
    var albumArtist: String?
    let play: (Int) -> Void
    @ViewBuilder var rowMenu: (Track) -> RowMenu

    @State private var selection: Track.ID?
    @FocusState private var isFocused: Bool

    var body: some View {
        LazyVStack(spacing: 0) {
            ForEach(Array(tracks.enumerated()), id: \.element.id) { index, track in
                TrackRow(track: track, number: track.number, isPreview: isPreview(track),
                         showsArtist: albumArtist.map { !track.artists.isEmpty && track.artists != $0 } ?? true,
                         isSelected: selection == track.id && isFocused,
                         isStriped: index.isMultiple(of: 2),
                         select: { selection = track.id; isFocused = true },
                         play: { play(index) }) {
                    rowMenu(track)
                }
            }
        }
        .focusable()
        .focused($isFocused)
        .focusEffectDisabled()
        .onKeyPress(.return) {
            guard let index = tracks.firstIndex(where: { $0.id == selection }) else { return .ignored }
            play(index)
            return .handled
        }
        .onKeyPress(.downArrow) { moveSelection(by: 1) }
        .onKeyPress(.upArrow) { moveSelection(by: -1) }
    }

    private func moveSelection(by offset: Int) -> KeyPress.Result {
        guard !tracks.isEmpty else { return .ignored }
        let current = tracks.firstIndex(where: { $0.id == selection }) ?? (offset > 0 ? -1 : tracks.count)
        let next = min(max(current + offset, 0), tracks.count - 1)
        selection = tracks[next].id
        return .handled
    }
}

extension TrackList where RowMenu == EmptyView {
    init(tracks: [Track], isPreview: @escaping (Track) -> Bool = { _ in false }, albumArtist: String? = nil,
         play: @escaping (Int) -> Void) {
        self.init(tracks: tracks, isPreview: isPreview, albumArtist: albumArtist, play: play, rowMenu: { _ in EmptyView() })
    }
}

private struct TrackRow<RowMenu: View>: View {
    let track: Track
    let number: String
    let isPreview: Bool
    let showsArtist: Bool
    let isSelected: Bool
    let isStriped: Bool
    let select: () -> Void
    let play: () -> Void
    @ViewBuilder var rowMenu: RowMenu
    @Environment(PlayerStore.self) private var player
    @State private var isHovering = false

    private var isCurrent: Bool { player.currentTrack?.id == track.id }

    var body: some View {
        HStack(spacing: 12) {
            leading
                .frame(width: 26, alignment: .center)
            HStack(spacing: 6) {
                Text(track.title)
                    .lineLimit(1)
                    .foregroundStyle(isCurrent ? Color.dizzyGold : .primary)
                if isPreview { TagBadge(text: "试听") }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            if showsArtist {
                Text(track.artists)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .frame(maxWidth: 260, alignment: .leading)
            }
            Text(track.duration.map(TimeFormat.clock) ?? "")
                .monospacedDigit()
                .foregroundStyle(.secondary)
                .frame(width: 48, alignment: .trailing)
            Menu {
                menuItems
            } label: {
                Image(systemName: "ellipsis")
                    .frame(width: 22, height: 22)
                    .contentShape(.rect)
            }
            .menuStyle(.button)
            .buttonStyle(.plain)
            .menuIndicator(.hidden)
            .fixedSize()
            .opacity(isHovering ? 1 : 0)
            .accessibilityLabel("\(track.title)的更多操作")
        }
        .padding(.horizontal, 10)
        .frame(height: 40)
        .background(background, in: .rect(cornerRadius: 6))
        .contentShape(.rect)
        .onHover { isHovering = $0 }
        .onTapGesture(count: 2, perform: play)
        .simultaneousGesture(TapGesture().onEnded(select))
        .contextMenu { menuItems }
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isButton)
        .accessibilityValue(isCurrent ? "当前播放" : "")
        .accessibilityAction(named: "播放", play)
    }

    private var background: Color {
        if isSelected { return Color.accentColor.opacity(0.22) }
        if isHovering { return Color.primary.opacity(0.07) }
        return isStriped ? Color.primary.opacity(0.025) : .clear
    }

    @ViewBuilder private var leading: some View {
        if isCurrent {
            if player.isLoading {
                ProgressView().controlSize(.mini)
            } else if isHovering {
                Button { player.togglePlayback() } label: {
                    Image(systemName: player.isPlaying ? "pause.fill" : "play.fill")
                }
                .buttonStyle(.plain)
                .foregroundStyle(Color.dizzyGold)
            } else {
                Image(systemName: "speaker.wave.2.fill")
                    .foregroundStyle(Color.dizzyGold)
                    .symbolEffect(.variableColor.iterative, options: .repeating, isActive: player.isPlaying)
            }
        } else if isHovering {
            Button(action: play) { Image(systemName: "play.fill") }
                .buttonStyle(.plain)
        } else {
            Text(number)
                .monospacedDigit()
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
        }
    }

    @ViewBuilder private var menuItems: some View {
        Button(isCurrent && player.isPlaying ? "暂停" : "播放", systemImage: isCurrent && player.isPlaying ? "pause" : "play") {
            if isCurrent { player.togglePlayback() } else { play() }
        }
        rowMenu
        Divider()
        Button("拷贝歌曲名称", systemImage: "doc.on.doc") {
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(track.title, forType: .string)
        }
    }
}

/// 专辑页脚：发行日期、曲目数与总时长。
struct TrackListFooter: View {
    let tracks: [Track]
    var releaseDate: String?

    var body: some View {
        let total = tracks.compactMap(\.duration).reduce(0, +)
        VStack(alignment: .leading, spacing: 2) {
            if let releaseDate { Text(releaseDate) }
            Text(total > 0 ? "\(tracks.count) 首歌曲，\(TimeFormat.total(total))" : "\(tracks.count) 首歌曲")
        }
        .font(.callout)
        .foregroundStyle(.secondary)
    }
}
