// 布局移植自 MeloX（GPLv3）Features/Player/NowPlaying/NowPlayingView.swift 的竖屏部分：
// 去掉歌词页、横屏和 Text PV，只保留大封面页和队列页。

import SwiftUI

/// 播放页：全屏展开（从迷你播放器的封面放大出来），下拉或点顶部的横条收起。
struct NowPlayingView: View {
    /// 迷你播放器封面和播放页之间缩放转场的标识。
    static let transitionID = "nowPlaying"
    /// 大封面和队列页小封面之间过渡的标识。
    static let artworkID = "nowPlayingArtwork"
    private static let horizontalPadding: CGFloat = 32

    @Environment(\.dismiss) private var dismiss
    @Environment(\.accessibilityReduceMotion) private var accessibilityReduceMotion
    @Environment(PlayerStore.self) private var player

    @State private var page: NowPlayingPage = .artwork
    @Namespace private var artworkNamespace

    var body: some View {
        ZStack {
            NowPlayingBackground(artworkURL: player.currentTrack?.coverURL)

            if let track = player.currentTrack {
                VStack(spacing: 0) {
                    dismissalHandle

                    ZStack(alignment: .top) {
                        switch page {
                        case .artwork:
                            NowPlayingArtworkPage(track: track, artworkNamespace: artworkNamespace)
                                .transition(.opacity)
                        case .queue:
                            NowPlayingQueuePage(track: track, artworkNamespace: artworkNamespace)
                                .transition(queueTransition)
                        }
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .overlay(alignment: .bottom) {
                        NowPlayingBottomControls(page: $page)
                    }
                }
                .padding(.horizontal, Self.horizontalPadding)
                .safeAreaPadding(.bottom, 3)
            }
        }
        .foregroundStyle(.white)
        .preferredColorScheme(.dark)
        .onChange(of: player.currentTrack == nil) { _, isEmpty in
            if isEmpty { dismiss() }
        }
    }

    /// 队列从上方稍微放大着淡入，与 MeloX 的队列出场一致。
    private var queueTransition: AnyTransition {
        accessibilityReduceMotion
            ? .opacity
            : .asymmetric(
                insertion: .opacity.combined(with: .scale(scale: 0.9, anchor: .top)),
                removal: .opacity
            )
    }

    /// 顶部的小横条：点一下收起播放页。下拉收起由缩放转场本身提供。
    private var dismissalHandle: some View {
        Capsule()
            .fill(.white.opacity(0.52))
            .frame(width: 60, height: 5)
            .padding(.top, 8)
            .frame(maxWidth: .infinity)
            .frame(height: 34, alignment: .top)
            .contentShape(.rect)
            .onTapGesture { dismiss() }
            .accessibilityElement()
            .accessibilityLabel("收起播放页")
            .accessibilityAddTraits(.isButton)
            .accessibilityAction { dismiss() }
    }
}
