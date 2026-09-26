// 移植自 MeloX（GPLv3）Features/Player/NowPlaying/NowPlayingArtworkPage.swift、NowPlayingSongHeader.swift、
// NowPlayingQueuePage.swift：去掉歌词页、收藏、一起听、AutoMix 和拖动排序；封面在两页之间用 matchedGeometryEffect 过渡。

import SwiftUI

/// 大封面页：暂停时封面缩小，开始播放时轻轻弹一下；下面是曲名、艺术家和「…」菜单。
struct NowPlayingArtworkPage: View {
    static let pausedArtworkScale: CGFloat = 0.74

    @Environment(\.accessibilityReduceMotion) private var accessibilityReduceMotion
    @Environment(PlayerStore.self) private var player

    let track: Track
    let artworkNamespace: Namespace.ID

    @State private var bounceScale: CGFloat = 1

    var body: some View {
        GeometryReader { proxy in
            let artworkSize = max(
                170,
                min(proxy.size.width + 16, proxy.size.height - NowPlayingBottomControls.coreHeight - 92)
            )
            let displayedSize = artworkSize * (player.isPlaying ? 1 : Self.pausedArtworkScale)

            VStack(spacing: 0) {
                Spacer(minLength: 8)

                ArtworkImage(url: track.coverURL, cornerRadius: 12)
                    .frame(width: displayedSize, height: displayedSize)
                    .matchedGeometryEffect(id: NowPlayingView.artworkID, in: artworkNamespace)
                    .scaleEffect(bounceScale)
                    .shadow(
                        color: .black.opacity(player.isPlaying ? 0.34 : 0.18),
                        radius: player.isPlaying ? 26 : 14,
                        y: player.isPlaying ? 15 : 8
                    )
                    .frame(width: artworkSize, height: artworkSize)
                    .animation(accessibilityReduceMotion ? nil : .smooth(duration: 0.48), value: player.isPlaying)
                    .accessibilityElement()
                    .accessibilityLabel("\(track.albumTitle)的封面")
                    .task(id: player.isPlaying) {
                        await bounce(whenPlaying: player.isPlaying)
                    }

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
            }
            .padding(.bottom, NowPlayingBottomControls.coreHeight)
            .frame(width: proxy.size.width, height: proxy.size.height)
        }
    }

    /// 开始播放时封面先放大一点再回弹。
    private func bounce(whenPlaying isPlaying: Bool) async {
        bounceScale = 1
        guard isPlaying, !accessibilityReduceMotion else { return }
        await Task.yield()
        withAnimation(.easeOut(duration: 0.17)) {
            bounceScale = 1.055
        }
        do {
            try await Task.sleep(for: .milliseconds(170))
        } catch {
            return
        }
        withAnimation(.spring(duration: 0.42, bounce: 0.24)) {
            bounceScale = 1
        }
    }
}

/// 队列页顶部的曲目信息：小封面、曲名、艺术家和「…」菜单。
struct NowPlayingSongHeader: View {
    static let height: CGFloat = 72

    let track: Track
    let artworkNamespace: Namespace.ID

    var body: some View {
        HStack(spacing: 12) {
            ArtworkImage(url: track.coverURL, cornerRadius: 12)
                .frame(width: Self.height, height: Self.height)
                .matchedGeometryEffect(id: NowPlayingView.artworkID, in: artworkNamespace)

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
    }
}

/// 「继续播放」队列：随机、循环两个开关，接下来要播放的曲目，点一下直接播放。
struct NowPlayingQueuePage: View {
    @Environment(PlayerStore.self) private var player

    let track: Track
    let artworkNamespace: Namespace.ID

    var body: some View {
        let upcoming = player.upcoming
        List {
            NowPlayingSongHeader(track: track, artworkNamespace: artworkNamespace)
                .listRowInsets(.init())
                .listRowSeparator(.hidden)
                .listRowBackground(Color.clear)

            Section {
                Text("继续播放")
                    .font(.title2.bold())
                    .padding(.top, 14)
                    .padding(.bottom, 10)
                    .listRowInsets(.init())
                    .listRowSeparator(.hidden)
                    .listRowBackground(Color.clear)

                if upcoming.isEmpty {
                    Text(player.isDiscovery ? "随便听听：下一首获取新曲目，上一首返回收听历史。" : player.repeatMode == .one ? "正在单曲循环" : "后面没有要播放的曲目了")
                        .font(.subheadline)
                        .foregroundStyle(.white.opacity(0.58))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 24)
                        .listRowInsets(.init())
                        .listRowSeparator(.hidden)
                        .listRowBackground(Color.clear)
                } else {
                    ForEach(upcoming) { entry in
                        NowPlayingQueueRow(entry: entry)
                    }
                }
            } header: {
                if !player.isDiscovery {
                    NowPlayingQueueModeControls()
                        .padding(.vertical, 8)
                        .textCase(nil)
                        .listRowInsets(.init())
                }
            }
        }
        .listStyle(.plain)
        .listSectionSpacing(0)
        .scrollContentBackground(.hidden)
        .contentMargins(.top, 0, for: .scrollContent)
        .contentMargins(.bottom, NowPlayingBottomControls.coreHeight, for: .scrollContent)
        .environment(\.defaultMinListRowHeight, 1)
        .environment(\.defaultMinListHeaderHeight, 0)
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
