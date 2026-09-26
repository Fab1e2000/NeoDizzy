// 移植自 MeloX（GPLv3）Features/Player/NowPlaying/AppleMusicBackdrop/NowPlayingAppleMusicBackground.swift
// 和 AppleMusicBackdropShader.swift：只保留 Apple Music 式背景，去掉随音频频谱变化和歌词页的扭曲过渡，
// 封面改用 Nuke 按缩略图加载。

import Nuke
import NukeUI
import SwiftUI

/// 播放页背景：封面缓慢旋转、扭曲并大幅模糊，随播放进度流动，暂停时停住。
struct NowPlayingBackground: View {
    @Environment(PlayerStore.self) private var player
    @Environment(\.accessibilityReduceMotion) private var accessibilityReduceMotion
    @Environment(\.isLuminanceReduced) private var isLuminanceReduced
    @Environment(\.scenePhase) private var scenePhase

    let artworkURL: URL?

    @State private var meshIndex = Int.random(in: 0..<5)

    private static let baseColor = Color(red: 0.18, green: 0.18, blue: 0.18)

    var body: some View {
        GeometryReader { proxy in
            TimelineView(.animation(minimumInterval: 1.0 / 60.0, paused: pausesAnimation)) { context in
                let time = animationTime(at: context.date)
                ZStack {
                    Self.baseColor

                    artwork(in: proxy.size)
                        .layerEffect(
                            ShaderLibrary.appleMusicBackdropRotation(
                                .float2(proxy.size),
                                .float(time),
                                // 不随音频变化：频谱固定为 0。
                                .float4(0, 0, 0, 0),
                                .float(1),
                                .float(0.5),
                                .float(1)
                            ),
                            maxSampleOffset: proxy.size
                        )
                        .blur(radius: 80, opaque: true)
                        .layerEffect(
                            ShaderLibrary.appleMusicBackdropPinch(
                                .float2(proxy.size),
                                .float(time),
                                .float(0),
                                .float(Float(meshIndex))
                            ),
                            maxSampleOffset: proxy.size
                        )

                    Color.white.opacity(0.1)

                    LinearGradient(colors: [.black.opacity(0), .black], startPoint: .top, endPoint: .bottom)
                        .opacity(0.4)
                }
                .frame(width: proxy.size.width, height: proxy.size.height)
                .clipped()
            }
        }
        .ignoresSafeArea()
        .accessibilityHidden(true)
    }

    private func artwork(in size: CGSize) -> some View {
        // 背景会被模糊 80 点，按小尺寸解码就够了。
        LazyImage(
            request: artworkURL.map { url in
                var request = ImageRequest(url: url)
                request.thumbnail = ImageRequest.ThumbnailOptions(size: CGSize(width: 300, height: 300), contentMode: .aspectFill)
                return request
            },
            transaction: Transaction(animation: accessibilityReduceMotion ? nil : .timingCurve(0, 0, 0.3, 1, duration: 0.8))
        ) { state in
            if let image = state.image {
                image
                    .resizable()
                    .scaledToFill()
                    .transition(.opacity)
            } else {
                Self.baseColor
            }
        }
        .id(artworkURL)
        .frame(width: size.width, height: size.height)
        .clipped()
    }

    private var pausesAnimation: Bool {
        accessibilityReduceMotion || isLuminanceReduced || scenePhase != .active || !player.isPlaying
    }

    private func animationTime(at date: Date) -> TimeInterval {
        pausesAnimation ? player.estimatedProgress() : player.estimatedProgress(at: date)
    }
}
