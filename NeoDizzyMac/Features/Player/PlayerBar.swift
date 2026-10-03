import SwiftUI

/// 窗口底部的浮动播放条（Liquid Glass），布局参考 macOS Tahoe 以后的 Music：
/// 左侧播放控制，中间封面、曲目信息与进度，右侧歌词、待播清单、AirPlay 和音量。
/// 窗口变窄时依次收起随机 / 循环和音量滑块。
struct PlayerBar: View {
    var body: some View {
        ViewThatFits(in: .horizontal) {
            PlayerBarLayout(showsModes: true, showsVolume: true)
            PlayerBarLayout(showsModes: false, showsVolume: true)
            PlayerBarLayout(showsModes: false, showsVolume: false)
        }
        .frame(height: 60)
        .glassEffect(.regular, in: .rect(cornerRadius: 18))
        // 不向分栏视图报告完整布局的理想宽度，否则打开右侧面板时详情栏不肯变窄。
        .frame(minWidth: 0, idealWidth: 0, maxWidth: .infinity)
    }
}

private struct PlayerBarLayout: View {
    let showsModes: Bool
    let showsVolume: Bool
    @Environment(MacAppModel.self) private var model

    var body: some View {
        HStack(spacing: 14) {
            TransportControls(showsModes: showsModes)
            NowPlayingDisplay()
                .frame(minWidth: 260, idealWidth: 460, maxWidth: 600)
            HStack(spacing: 2) {
                Button { model.togglePanel(.lyrics) } label: {
                    Image(systemName: "quote.bubble").font(.system(size: 14))
                }
                .buttonStyle(PlayerButtonStyle(isActive: model.playerPanel == .lyrics))
                .help("歌词")
                Button { model.togglePanel(.queue) } label: {
                    Image(systemName: "list.bullet").font(.system(size: 14, weight: .medium))
                }
                .buttonStyle(PlayerButtonStyle(isActive: model.playerPanel == .queue))
                .help("待播清单")
                AirPlayButton()
                    .frame(width: 28, height: 28)
                    .help("AirPlay")
                if showsVolume {
                    VolumeControl()
                        .padding(.leading, 4)
                }
            }
        }
        .padding(.horizontal, 14)
    }
}

/// 播放条中间的「LCD」：封面、标题、艺术家与进度。
struct NowPlayingDisplay: View {
    @Environment(MacAppModel.self) private var model
    @Environment(PlayerStore.self) private var player

    var body: some View {
        HStack(spacing: 10) {
            Button { model.togglePanel(.lyrics) } label: {
                ArtworkImage(url: player.currentTrack?.coverURL, cornerRadius: 5)
                    .frame(width: 40, height: 40)
            }
            .buttonStyle(.plain)
            .disabled(player.currentTrack == nil)
            .help("歌词")
            if let track = player.currentTrack {
                VStack(spacing: 2) {
                    HStack(spacing: 6) {
                        VStack(alignment: .leading, spacing: 0) {
                            Button {
                                if let route = model.currentAlbumRoute { model.open(route) }
                            } label: {
                                Text(track.title)
                                    .font(.callout.weight(.semibold))
                                    .lineLimit(1)
                            }
                            .buttonStyle(.plain)
                            .help("前往专辑")
                            subtitle(track)
                                .font(.caption)
                                .lineLimit(1)
                        }
                        Spacer(minLength: 4)
                        if player.isLoading {
                            ProgressView().controlSize(.mini)
                        } else if player.isPreview {
                            TagBadge(text: "试听")
                        }
                    }
                    ProgressScrubber()
                }
            } else {
                Text("NeoDizzy")
                    .font(.callout.weight(.semibold))
                    .foregroundStyle(.tertiary)
                    .frame(maxWidth: .infinity)
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 5)
        .background(.primary.opacity(0.05), in: .rect(cornerRadius: 10))
    }

    @ViewBuilder private func subtitle(_ track: Track) -> some View {
        if let issue = player.issue {
            Text(issue).foregroundStyle(DizzyPalette.danger)
        } else {
            Text([track.artists, track.albumTitle].filter { !$0.isEmpty }.joined(separator: " — "))
                .foregroundStyle(.secondary)
        }
    }
}
