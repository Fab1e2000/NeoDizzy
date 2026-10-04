import SwiftUI

/// 窗口底部贴边的播放条，分三栏：
/// 左栏封面与曲目信息，中栏播放控制和其下的进度条，右栏歌词、待播清单、AirPlay 与音量。
/// 三栏位置由 `PlayerBarLayout` 在每次布局时直接按播放条宽度计算：中栏始终位于正中、宽度按比例伸缩，
/// 左右两栏严格等宽。窗口很窄时依次收起次要控件。
struct PlayerBar: View {
    @Environment(MacAppModel.self) private var model
    @Environment(PlayerStore.self) private var player
    /// 只在跨过控件的显示阈值时更新，避免分栏动画逐帧写回状态。
    @State private var controlVisibility = PlayerBarControlVisibility(width: 1000)
    @State private var showsVolumePopover = false

    private var showsModes: Bool { controlVisibility.showsModes }
    private var showsVolumeSlider: Bool { controlVisibility.showsVolumeSlider }

    var body: some View {
        PlayerBarLayout {
            NowPlayingInfo()
            VStack(spacing: 4) {
                TransportControls(showsModes: showsModes)
                ProgressScrubber(showsTimes: showsVolumeSlider)
            }
            tools
        }
        .padding(.horizontal, 16)
        .frame(maxWidth: .infinity)
        .frame(height: PageMetrics.playerBarInset)
        .background(.background)
        .overlay(alignment: .top) { Divider() }
        .onGeometryChange(for: PlayerBarControlVisibility.self) {
            PlayerBarControlVisibility(width: $0.size.width)
        } action: { controlVisibility = $0 }
        // 不向分栏视图报告理想宽度，详情栏可以自由变窄。
        .frame(minWidth: 0, idealWidth: 0, maxWidth: .infinity)
    }

    private var tools: some View {
        HStack(spacing: 2) {
            if !showsModes { modesMenu }
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
            if showsVolumeSlider {
                VolumeControl(width: 96)
                    .padding(.leading, 4)
            } else {
                Button { showsVolumePopover.toggle() } label: {
                    Image(systemName: player.volume == 0 ? "speaker.slash.fill" : "speaker.wave.2.fill")
                        .font(.system(size: 12, weight: .medium))
                }
                .buttonStyle(PlayerButtonStyle())
                .help("音量")
                .popover(isPresented: $showsVolumePopover, arrowEdge: .top) {
                    VolumeControl(width: 140).padding(12)
                }
            }
        }
    }

    /// 窄窗口里的随机与循环。
    private var modesMenu: some View {
        Menu {
            Toggle("随机播放", isOn: Binding(get: { player.isShuffled }, set: { if $0 != player.isShuffled { player.toggleShuffle() } }))
            Button("循环：\(player.repeatMode.accessibilityTitle)") { player.cycleRepeatMode() }
        } label: {
            Image(systemName: "ellipsis").font(.system(size: 13, weight: .semibold))
        }
        .menuStyle(.button)
        .menuIndicator(.hidden)
        .buttonStyle(PlayerButtonStyle(isActive: player.isShuffled || player.repeatMode != .off))
        .fixedSize()
        .disabled(player.currentTrack == nil || player.isDiscovery)
        .help("随机与循环")
    }
}

/// 播放条的三栏布局。依次接收左栏、中栏、右栏三个子视图。
///
/// - 中栏宽度 = 总宽度的 42%，限制在 220–860 之间，并且保证两侧至少放得下右栏工具按钮。
/// - 左右两栏各占剩余宽度的一半；左栏内容靠左，右栏内容靠右，中栏在正中。
/// - 三栏都垂直居中。
private struct PlayerBarLayout: Layout {
    var spacing: CGFloat = 16

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let height = subviews.map { $0.sizeThatFits(.unspecified).height }.max() ?? 0
        return CGSize(width: proposal.width ?? 800, height: proposal.height ?? height)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        guard subviews.count == 3 else { return }
        let total = bounds.width
        // 右栏工具按钮的固有宽度：两侧至少要放得下它。
        let toolsWidth = subviews[2].sizeThatFits(.unspecified).width
        let minSide = max(toolsWidth, 140)
        let maxCenter = total - spacing * 2 - minSide * 2
        let center = max(min(total * 0.42, 860, maxCenter), min(220, max(maxCenter, 0)))
        let side = max((total - center - spacing * 2) / 2, 0)

        let midY = bounds.midY
        subviews[0].place(at: CGPoint(x: bounds.minX, y: midY), anchor: .leading,
                          proposal: ProposedViewSize(width: side, height: bounds.height))
        subviews[1].place(at: CGPoint(x: bounds.midX, y: midY), anchor: .center,
                          proposal: ProposedViewSize(width: center, height: bounds.height))
        subviews[2].place(at: CGPoint(x: bounds.maxX, y: midY), anchor: .trailing,
                          proposal: ProposedViewSize(width: side, height: bounds.height))
    }
}

/// 播放条左栏：封面、标题和艺术家。点封面打开歌词，点标题前往专辑。
private struct NowPlayingInfo: View {
    @Environment(MacAppModel.self) private var model
    @Environment(PlayerStore.self) private var player

    var body: some View {
        HStack(spacing: 10) {
            Button { model.togglePanel(.lyrics) } label: {
                ArtworkImage(url: player.currentTrack?.coverURL, cornerRadius: 5, decodeSize: CGSize(width: 112, height: 112))
                    .frame(width: 48, height: 48)
            }
            .buttonStyle(.plain)
            .disabled(player.currentTrack == nil)
            .help("歌词")
            if let track = player.currentTrack {
                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 6) {
                        Button {
                            if let route = model.currentAlbumRoute { model.open(route) }
                        } label: {
                            Text(track.title)
                                .font(.callout.weight(.semibold))
                                .lineLimit(1)
                        }
                        .buttonStyle(.plain)
                        .help("前往专辑")
                        if player.isLoading {
                            ProgressView().controlSize(.mini)
                        } else if player.isPreview {
                            TagBadge(text: "试听")
                        }
                    }
                    subtitle(track)
                        .font(.caption)
                        .lineLimit(1)
                }
            } else {
                Text("未在播放")
                    .font(.callout)
                    .foregroundStyle(.tertiary)
            }
        }
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
