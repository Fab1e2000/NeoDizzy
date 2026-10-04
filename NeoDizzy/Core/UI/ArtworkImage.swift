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
    var contentMode: ContentMode = .fill

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
            size: decodeSize ?? Self.bucketed(size),
            contentMode: contentMode == .fit ? .aspectFit : .aspectFill
        )
        return request
    }

    /// 解码尺寸按 128 点向上取整：拖动窗口时同一档位内复用同一个请求，不会每一帧都重新解码。
    private static func bucketed(_ size: CGSize) -> CGSize {
        func round(_ value: CGFloat) -> CGFloat { (max(value, 1) / 128).rounded(.up) * 128 }
        return CGSize(width: round(size.width), height: round(size.height))
    }

    private var imageLoadAnimation: Animation? {
        accessibilityReduceMotion ? nil : .easeOut(duration: 0.18)
    }

    @ViewBuilder
    private func content(image: Image?, hasError: Bool) -> some View {
        if let image {
            image
                .resizable()
                .aspectRatio(contentMode: contentMode)
                .transition(.opacity)
        } else if hasError || url == nil {
            ZStack {
                DizzyPalette.artworkPlaceholder
                Image(systemName: "music.note")
                    .font(.title2)
                    .foregroundStyle(DizzyPalette.artworkPlaceholderSymbol)
            }
        } else {
            DizzyPalette.artworkPlaceholder
        }
    }
}
