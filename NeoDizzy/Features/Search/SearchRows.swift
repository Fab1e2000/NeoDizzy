import SwiftUI

// Adapted from MeloX Features/Song/TrackRowView.swift and Features/Search/SearchView.swift (GPL-3.0).

/// 歌曲行：封面或序号、歌名、歌手 · 专辑，已下载标记和时长；长按是歌曲操作菜单。
struct TrackListRow: View {
    let track: Track
    var index: Int?
    var showsArtwork = false
    var isDownloaded = false
    var additionalActions: [AlbumRowAction] = []
    @State private var songActions = SongActionPresentation()
    @Environment(PlayerStore.self) private var player

    var body: some View {
        HStack(spacing: 12) {
            if showsArtwork {
                ArtworkImage(url: track.coverURL, cornerRadius: 6)
                    .frame(width: 44, height: 44)
                    .overlay {
                        if player.currentTrack?.id == track.id {
                            RoundedRectangle(cornerRadius: 6).fill(.black.opacity(0.35))
                            Image(systemName: player.isPlaying ? "waveform" : "pause.fill")
                                .font(.caption.weight(.bold)).foregroundStyle(.white)
                        }
                    }
            } else if let index {
                Text((index + 1).formatted())
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
                    .frame(width: 26, alignment: .trailing)
            }
            VStack(alignment: .leading, spacing: 3) {
                Text(track.title)
                    .font(.body)
                    .foregroundStyle(player.currentTrack?.id == track.id ? DizzyPalette.accent : DizzyPalette.text)
                    .lineLimit(1)
                Text(subtitle)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            Spacer(minLength: 8)
            if isDownloaded {
                Image(systemName: "arrow.down.circle.fill")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .accessibilityLabel("已下载")
            }
            if let duration = track.duration, duration > 0 {
                Text(Duration.seconds(duration).formatted(.time(pattern: .minuteSecond)))
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
            }
        }
        .contentShape(.rect)
        .contextMenu {
            SongLibraryActions(track: track, presentation: songActions)
            ForEach(additionalActions) { action in
                Button(action.title, systemImage: action.systemImage, action: action.perform).disabled(action.disabled)
            }
        }
        .modifier(SongActionPresentationModifier(track: track, presentation: songActions))
    }

    private var subtitle: String {
        [track.artists, track.albumTitle].filter { !$0.isEmpty }.joined(separator: " · ")
    }
}

/// 专辑、歌单、歌手、社团的一行：54pt 封面（歌手、社团为圆形）、名称和一行说明。
struct SearchMediaRow: View {
    let title: String
    let subtitle: String?
    let artworkURL: URL?
    var circular = false

    var body: some View {
        HStack(spacing: 12) {
            ArtworkImage(url: artworkURL, cornerRadius: circular ? 1_000 : 7)
                .frame(width: 54, height: 54)
            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .foregroundStyle(DizzyPalette.text)
                    .lineLimit(1)
                if let subtitle, !subtitle.isEmpty {
                    Text(subtitle)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }
            Spacer(minLength: 0)
        }
        .contentShape(.rect)
    }
}

/// 统一搜索里的一组结果：标题行，下面是像分组列表一样的圆角卡片。
struct SearchGroup<Content: View>: View {
    let title: String
    var allResults: AppRoute?
    @ViewBuilder var content: () -> Content

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            SearchSectionHeader(title: title, allResults: allResults)
                .padding(.horizontal, 4)
            VStack(alignment: .leading, spacing: 0) { content() }
                .padding(.horizontal, 16)
                .background(DizzyPalette.surface, in: .rect(cornerRadius: 12))
        }
    }
}

/// 卡片里的一行：上下留白，除最后一行外底部有与文字对齐的分隔线。
struct SearchCardRow<Content: View>: View {
    var isLast = false
    var separatorInset: CGFloat = 56
    @ViewBuilder var content: () -> Content

    var body: some View {
        content()
            .padding(.vertical, 8)
            .frame(maxWidth: .infinity, alignment: .leading)
            .overlay(alignment: .bottom) {
                if !isLast {
                    Rectangle().fill(Color(uiColor: .separator)).frame(height: 0.5).padding(.leading, separatorInset)
                }
            }
    }
}
