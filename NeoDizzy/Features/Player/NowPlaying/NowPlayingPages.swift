// 移植自 MeloX（GPLv3）Features/Player/NowPlaying/NowPlayingArtworkPage.swift、NowPlayingSongHeader.swift、
// NowPlayingQueuePage.swift：保留现有播放功能，两个页面通过单一封面层过渡。

import SwiftUI

/// 大封面页：暂停时封面缩小，开始播放时轻轻弹一下；下面是曲名、艺术家和「…」菜单。
struct NowPlayingArtworkPage: View {
    static let pausedArtworkScale: CGFloat = 0.74

    @Environment(\.accessibilityReduceMotion) private var accessibilityReduceMotion
    @Environment(PlayerStore.self) private var player

    let track: Track
    let controlsHeight: CGFloat
    let onArtworkFrameChange: (CGRect) -> Void

    @State private var titleHeight: CGFloat = 52

    var body: some View {
        GeometryReader { proxy in
            let artworkSize = max(
                0,
                min(proxy.size.width, proxy.size.height - controlsHeight - titleHeight - 30)
            )

            VStack(spacing: 0) {
                Spacer(minLength: 8)

                Color.clear
                    .frame(width: artworkSize, height: artworkSize)
                    .onGeometryChange(for: CGRect.self) { $0.frame(in: .global) } action: { onArtworkFrameChange($0) }
                    .frame(width: artworkSize, height: artworkSize)

                Spacer(minLength: 22)

                HStack(spacing: 14) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(track.title)
                            .font(.title3.weight(.semibold))
                            .lineLimit(1)
                        Text(track.artists)
                            .font(.title3)
                            .foregroundStyle(.white.opacity(0.64))
                            .lineLimit(1)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)

                    NowPlayingSongActions(track: track)
                }
                .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { titleHeight = $0 }
            }
            .padding(.bottom, controlsHeight)
            .frame(width: proxy.size.width, height: proxy.size.height)
        }
    }

}

/// Only one visible artwork exists across both resident pages.
struct PlayerTransitionArtwork: View {
    let track: Track
    let expanded: Bool
    @Environment(PlayerStore.self) private var player
    @Environment(\.accessibilityReduceMotion) private var accessibilityReduceMotion
    private var scale: CGFloat {
        expanded && !player.isPlaying ? NowPlayingArtworkPage.pausedArtworkScale : 1
    }

    var body: some View {
        ArtworkImage(url: track.coverURL, cornerRadius: 12)
            .scaleEffect(scale)
            // A single interruptible spring owns the visible cover, not a measured placeholder.
            .animation(accessibilityReduceMotion ? nil : .spring(duration: 0.48, bounce: 0.12), value: player.isPlaying)
            .animation(accessibilityReduceMotion ? nil : .smooth(duration: 0.4), value: expanded)
    }
}

/// 队列页顶部的曲目信息：小封面、曲名、艺术家和「…」菜单。
struct NowPlayingSongHeader: View {
    static let height: CGFloat = 72

    let track: Track
    let onArtworkFrameChange: (CGRect) -> Void
    var onImportLyrics: (() -> Void)? = nil

    var body: some View {
        HStack(spacing: 12) {
            Color.clear
                .frame(width: Self.height, height: Self.height)
                .onGeometryChange(for: CGRect.self) { $0.frame(in: .global) } action: { onArtworkFrameChange($0) }

            VStack(alignment: .leading, spacing: 2) {
                Text(track.title)
                    .font(.title3.weight(.semibold))
                    .lineLimit(1)
                Text(track.artists)
                    .font(.title3)
                    .foregroundStyle(.white.opacity(0.64))
                    .lineLimit(1)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            NowPlayingSongActions(track: track, onImportLyrics: onImportLyrics)
        }
    }
}

/// 「继续播放」队列：随机、循环两个开关，接下来要播放的曲目，点一下直接播放。
struct NowPlayingQueuePage: View {
    @Environment(PlayerStore.self) private var player

    let track: Track
    let controlsHeight: CGFloat
    let onArtworkFrameChange: (CGRect) -> Void

    var body: some View {
        let upcoming = player.upcoming
        ScrollView {
            LazyVStack(spacing: 0, pinnedViews: [.sectionHeaders]) {
                NowPlayingSongHeader(track: track, onArtworkFrameChange: onArtworkFrameChange)
                    .padding(.bottom, 8)
                Section {
                    Text("继续播放")
                        .font(.title2.bold())
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.top, 14).padding(.bottom, 10)
                    if upcoming.isEmpty {
                        Text(player.isDiscovery ? "随便听听：下一首获取新曲目，上一首返回收听历史。" : player.repeatMode == .one ? "正在单曲循环" : "后面没有要播放的曲目了")
                            .font(.subheadline).foregroundStyle(.white.opacity(0.58))
                            .frame(maxWidth: .infinity).padding(.vertical, 24)
                    } else {
                        ForEach(upcoming) { entry in
                            NowPlayingQueueRow(entry: entry).padding(.vertical, 4)
                        }
                    }
                } header: {
                    if !player.isDiscovery {
                        NowPlayingQueueModeControls()
                            .padding(.vertical, 8)
                            .background(.ultraThinMaterial, in: .rect(cornerRadius: 22))
                    }
                }
            }
        }
        .padding(.bottom, controlsHeight)
    }
}

/// 随机播放、循环模式。选中时白底。
private struct NowPlayingQueueModeControls: View {
    @Environment(PlayerStore.self) private var player

    var body: some View {
        HStack(spacing: 14) {
            modeButton(
                systemImage: "shuffle",
                isSelected: player.isShuffled,
                accessibilityLabel: player.isShuffled ? "关闭随机播放" : "随机播放"
            ) {
                withAnimation(.smooth(duration: 0.34)) { player.toggleShuffle() }
            }
            modeButton(
                systemImage: player.repeatMode.systemImage,
                isSelected: player.repeatMode != .off,
                accessibilityLabel: player.repeatMode.accessibilityTitle
            ) {
                withAnimation(.smooth(duration: 0.34)) { player.cycleRepeatMode() }
            }
        }
    }

    private func modeButton(
        systemImage: String,
        isSelected: Bool,
        accessibilityLabel: String,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .contentTransition(.symbolEffect(.replace.downUp.wholeSymbol))
                .font(.title3.weight(.semibold))
                .frame(maxWidth: .infinity)
                .frame(height: 44)
                .foregroundStyle(isSelected ? .black.opacity(0.62) : .white.opacity(0.86))
                .background(.white.opacity(isSelected ? 0.7 : 0.12), in: .rect(cornerRadius: 22))
                .contentShape(.rect(cornerRadius: 22))
        }
        .buttonStyle(.plain)
        .accessibilityLabel(accessibilityLabel)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}

private struct NowPlayingQueueRow: View {
    @Environment(PlayerStore.self) private var player

    let entry: UpcomingTrack

    var body: some View {
        Button {
            player.playFromQueue(at: entry.index)
        } label: {
            HStack(spacing: 12) {
                ArtworkImage(url: entry.track.coverURL, cornerRadius: 6)
                    .frame(width: 48, height: 48)
                VStack(alignment: .leading, spacing: 2) {
                    Text(entry.track.title)
                        .font(.body)
                        .lineLimit(1)
                    Text(entry.track.artists)
                        .font(.subheadline)
                        .foregroundStyle(.white.opacity(0.58))
                        .lineLimit(1)
                }
                Spacer(minLength: 4)
                if let duration = entry.track.duration {
                    Text(Duration.seconds(duration).formatted(.time(pattern: .minuteSecond)))
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(.white.opacity(0.5))
                }
            }
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .listRowInsets(.init(top: 4, leading: 0, bottom: 4, trailing: 0))
        .listRowSeparator(.hidden)
        .listRowBackground(Color.clear)
    }
}
