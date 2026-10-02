// 移植自 MeloX（GPLv3）Shared/Media/ArtworkImage.swift：占位改用 DizzyPalette。

import Nuke
import NukeUI
import SwiftUI

/// 封面图。按显示尺寸解码缩略图，滚出屏幕时降低加载优先级。
struct ArtworkImage: View {
    let url: URL?
    var cornerRadius: CGFloat = 10
    var aspectRatio: CGFloat = 1
    var decodeSize: CGSize? = nil

    @Environment(\.accessibilityReduceMotion) private var accessibilityReduceMotion

    var body: some View {
        GeometryReader { proxy in
            LazyImage(
                request: imageRequest(for: proxy.size),
                transaction: Transaction(animation: imageLoadAnimation)
            ) { state in
                content(image: state.image, hasError: state.error != nil)
                    .frame(width: proxy.size.width, height: proxy.size.height)
            }
            .onDisappear(.lowerPriority)
        }
        .aspectRatio(aspectRatio, contentMode: .fit)
        .clipShape(.rect(cornerRadius: cornerRadius))
        .accessibilityHidden(true)
    }

    private func imageRequest(for size: CGSize) -> ImageRequest? {
        guard let url else { return nil }
        var request = ImageRequest(url: url)
        request.thumbnail = ImageRequest.ThumbnailOptions(
            size: decodeSize ?? CGSize(width: max(size.width, 1), height: max(size.height, 1)),
            contentMode: .aspectFill
        )
        return request
    }

    private var imageLoadAnimation: Animation? {
        accessibilityReduceMotion ? nil : .easeOut(duration: 0.18)
    }

    @ViewBuilder
    private func content(image: Image?, hasError: Bool) -> some View {
        if let image {
            image
                .resizable()
                .scaledToFill()
                .transition(.opacity)
        } else if hasError || url == nil {
            ZStack {
                DizzyPalette.surface
                Image(systemName: "music.note")
                    .font(.title2)
                    .foregroundStyle(DizzyPalette.mutedText)
            }
        } else {
            DizzyPalette.surface
        }
    }
}
