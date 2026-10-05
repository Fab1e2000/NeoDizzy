// 布局移植自 MeloX（GPLv3）Features/Player/NowPlaying/NowPlayingView.swift 的竖屏部分：
// 保留封面和队列布局，歌词由本地文件读取。

import SwiftUI

/// 播放页：全屏展开（从迷你播放器的封面放大出来），下拉或点顶部的横条收起。
struct NowPlayingView: View {
    private static let horizontalPadding: CGFloat = 32

    static let transitionID = "nowPlaying"
    @Environment(\.dismiss) private var dismiss
    @Environment(\.accessibilityReduceMotion) private var accessibilityReduceMotion
    @Environment(PlayerStore.self) private var player

    @State private var allowsGestureDismissal = false
    @State private var isLyricsInterfaceHidden = false
    @State private var page: NowPlayingPage = .artwork
    @State private var controlsHeight: CGFloat = NowPlayingBottomControls.coreHeight
    @State private var artworkFrame: CGRect = .zero
    @State private var queueFrame: CGRect = .zero
    @State private var lyricsFrame: CGRect = .zero
    @State private var playerFrame: CGRect = .zero
    @State private var contentOrigin: CGPoint = .zero

    var body: some View {
        ZStack {
            NowPlayingBackground(artworkURL: player.currentTrack?.coverURL)

            if let track = player.currentTrack {
                VStack(spacing: 0) {
                    dismissalHandle

                    ZStack(alignment: .top) {
                        NowPlayingLyricsPage(track: track, playerFrame: playerFrame, controlsHeight: controlsHeight, isActive: page == .lyrics, isInterfaceHidden: $isLyricsInterfaceHidden) { lyricsFrame = $0 }
                            .opacity(page == .lyrics ? 1 : 0)
                            .allowsHitTesting(page == .lyrics)
                            .accessibilityHidden(page != .lyrics)
                        NowPlayingArtworkPage(track: track, controlsHeight: controlsHeight) { artworkFrame = $0 }
                            .opacity(page == .artwork ? 1 : 0)
                            .allowsHitTesting(page == .artwork)
                            .accessibilityHidden(page != .artwork)
                        NowPlayingQueuePage(track: track, controlsHeight: controlsHeight) { queueFrame = $0 }
                            .opacity(page == .queue ? 1 : 0)
                            .allowsHitTesting(page == .queue)
                            .accessibilityHidden(page != .queue)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .onGeometryChange(for: CGPoint.self) { $0.frame(in: .global).origin } action: { contentOrigin = $0 }
                    .overlay(alignment: .topLeading) {
                        let frame = (page == .artwork ? artworkFrame : page == .queue ? queueFrame : lyricsFrame)
                            .offsetBy(dx: -contentOrigin.x, dy: -contentOrigin.y)
                        if frame.width > 0 {
                            PlayerTransitionArtwork(track: track, expanded: page == .artwork)
                                .frame(width: frame.width, height: frame.height)
                                .position(x: frame.midX, y: frame.midY)
                                .opacity(page == .queue && frame.minY < 0 ? 0 : 1)
                                .animation(accessibilityReduceMotion ? nil : .smooth(duration: 0.4), value: page)
                                .allowsHitTesting(false).accessibilityHidden(true)
                        }
                    }
                    .clipped()
                    .overlay(alignment: .bottom) {
                        NowPlayingBottomControls(page: $page)
                            .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { controlsHeight = $0 }
                            .opacity(isLyricsInterfaceHidden ? 0 : 1)
                            .offset(y: isLyricsInterfaceHidden ? controlsHeight : 0)
                            .allowsHitTesting(!isLyricsInterfaceHidden)
                            .accessibilityHidden(isLyricsInterfaceHidden)
                            .animation(accessibilityReduceMotion ? nil : .smooth(duration: 0.35), value: isLyricsInterfaceHidden)
                    }
                }
                .padding(.horizontal, Self.horizontalPadding)
                .safeAreaPadding(.bottom, 3)
            }
        }
        .interactiveDismissDisabled(!allowsGestureDismissal)
        .task {
            allowsGestureDismissal = false
            do { try await Task.sleep(for: .seconds(1)) } catch { return }
            allowsGestureDismissal = true
        }
        .onDisappear { allowsGestureDismissal = false }
        .onGeometryChange(for: CGRect.self) { $0.frame(in: .global) } action: { playerFrame = $0 }
        .onChange(of: page) { _, _ in isLyricsInterfaceHidden = false }
        .foregroundStyle(.white)
        // 播放页铺着封面取色的深色背景，不随 App 外观变化。只改环境、不用 preferredColorScheme，
        // 否则偏好会冒泡到整个窗口，下面的页面也跟着变深。
        .environment(\.colorScheme, .dark)
        .onChange(of: player.currentTrack == nil) { _, isEmpty in
            if isEmpty { dismiss() }
        }
    }

    /// 下拉收起由系统缩放转场提供。
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
