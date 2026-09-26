// 移植自 MeloX（GPLv3）Features/Player/MiniPlayer/MiniPlayerView.swift：去掉播放按钮的点击死区。

import SwiftUI

/// 标签栏上方的迷你播放器。标签栏收起时（inline）只显示封面、标题和播放按钮。
struct MiniPlayerView: View {
    @Environment(\.accessibilityReduceMotion) private var accessibilityReduceMotion
    @Environment(\.tabViewBottomAccessoryPlacement) private var placement
    @Environment(PlayerStore.self) private var player

    /// 封面是播放页缩放展开的起点。
    let transitionNamespace: Namespace.ID
    let onExpand: () -> Void

    var body: some View {
        if let track = player.currentTrack {
            HStack(spacing: isInline ? 8 : 10) {
                Button(action: onExpand) {
                    HStack(spacing: isInline ? 8 : 10) {
                        ArtworkImage(url: track.coverURL, cornerRadius: 6)
                            .frame(width: artworkSize, height: artworkSize)
                            .matchedTransitionSource(id: NowPlayingView.transitionID, in: transitionNamespace)
                        VStack(alignment: .leading, spacing: 1) {
                            Text(track.title)
                                .font(.subheadline.weight(.semibold))
                                .lineLimit(1)
                            if !isInline {
                                Text(track.artists)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                    .lineLimit(1)
                            }
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .contentShape(.rect)
                }
                .buttonStyle(.plain)
                .accessibilityHint("打开播放页")

                if player.isLoading {
                    ProgressView()
                        .controlSize(.small)
                        .frame(width: 36, height: 36)
                } else {
                    Button {
                        player.togglePlayback()
                    } label: {
                        Image(systemName: player.isPlaying ? "pause.fill" : "play.fill")
                            .font(.title3.weight(.semibold))
                            .contentTransition(
                                accessibilityReduceMotion
                                    ? .identity
                                    : .symbolEffect(.replace.downUp.wholeSymbol, options: .speed(1.6))
                            )
                            .frame(width: 36, height: 36)
                            .contentShape(.circle)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(player.isPlaying ? "暂停" : "播放")
                }

                if !isInline {
                    Button {
                        player.next()
                    } label: {
                        Image(systemName: "forward.fill")
                            .font(.title3.weight(.semibold))
                            .frame(width: 36, height: 36)
                            .contentShape(.circle)
                    }
                    .buttonStyle(.plain)
                    .disabled(!player.canPlayNext)
                    .accessibilityLabel("下一首")
                }
            }
            .padding(.horizontal, isInline ? 8 : 12)
            .padding(.vertical, isInline ? 3 : 6)
            .frame(maxWidth: .infinity)
            .contentShape(.rect)
            .accessibilityAction(named: "上一首") { player.previous() }
            .accessibilityAction(named: "下一首") { player.next() }
        }
    }

    private var isInline: Bool {
        placement == .inline
    }

    private var artworkSize: CGFloat {
        isInline ? 30 : 40
    }
}
