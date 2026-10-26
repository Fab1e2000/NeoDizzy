import Nuke
import SwiftUI
import UIKit

extension EnvironmentValues {
    /// 播放页背景在内容坐标系里的位置；整个播放器移动时保持不变。
    @Entry var nowPlayingBackdropFrame: CGRect = .zero
}

extension View {
    /// 在这个视图底下垫一份和播放页背景完全对齐的副本。
    /// 外层有遮罩或透明度时内容会单独合成，叠加提亮的文字碰不到真背景，只能和副本叠加；
    /// 副本和真背景重合，遮罩渐隐的地方也看不出来。
    func nowPlayingBackdropUnderlay(artworkURL: URL?) -> some View {
        background {
            NowPlayingBackdropUnderlay(artworkURL: artworkURL)
        }
    }
}

private struct NowPlayingBackdropUnderlay: View {
    let artworkURL: URL?
    @Environment(\.nowPlayingBackdropFrame) private var backdropFrame

    var body: some View {
        GeometryReader { proxy in
            let frame = proxy.frame(in: .named(NowPlayingContentCoordinateSpace.name))
            NowPlayingArtworkBackdrop(artworkURL: artworkURL, ignoresSafeArea: false, isUnderlay: true)
                .frame(width: backdropFrame.width, height: backdropFrame.height)
                .offset(x: backdropFrame.minX - frame.minX, y: backdropFrame.minY - frame.minY)
        }
        .allowsHitTesting(false)
    }
}

/// 播放页背景：放大、模糊的封面。换歌时新旧封面交叉淡入，不闪黑。
struct NowPlayingArtworkBackdrop: View {
    let artworkURL: URL?
    var ignoresSafeArea = true
    /// 作为背景副本画在别的视图底下：没有封面时完全透明（露出真背景），不画黑色打底和压暗。
    var isUnderlay = false
    /// 背景实际铺开的范围（含安全区），给背景副本对齐用。
    var onFrameChange: ((CGRect) -> Void)? = nil

    @Environment(\.accessibilityReduceMotion) private var accessibilityReduceMotion
    @State private var image: UIImage?

    init(
        artworkURL: URL?,
        ignoresSafeArea: Bool = true,
        isUnderlay: Bool = false,
        onFrameChange: ((CGRect) -> Void)? = nil
    ) {
        self.artworkURL = artworkURL
        self.ignoresSafeArea = ignoresSafeArea
        self.isUnderlay = isUnderlay
        self.onFrameChange = onFrameChange
        // 已经缓存的封面直接拿来用，第一次出现就有图，不会先黑一下再淡入。
        _image = State(initialValue: Self.request(for: artworkURL).flatMap {
            ImagePipeline.shared.cache.cachedImage(for: $0)?.image
        })
    }

    private static func request(for url: URL?) -> ImageRequest? {
        guard let url else { return nil }
        var request = ImageRequest(url: url)
        request.thumbnail = .init(size: decodeSize, unit: .pixels, contentMode: .aspectFill)
        return request
    }

    /// 只用来模糊，解码一张小图就够了。
    private static let decodeSize = CGSize(width: 240, height: 240)
    /// 按系统音乐截图校准：偏亮的封面压暗后，背景亮度约 110～125。
    private static let dimming = 0.22

    var body: some View {
        GeometryReader { proxy in
            ZStack {
                if !isUnderlay {
                    Color.black
                }

                if let image {
                    Image(uiImage: image)
                        .resizable()
                        .scaledToFill()
                        .frame(width: proxy.size.width, height: proxy.size.height)
                        // 放大后边缘的颜色不会在模糊时被拉进来，四周也不会露出黑边。
                        .scaleEffect(1.4)
                        .blur(radius: 60, opaque: true)
                        .id(image)
                        .transition(.opacity)
                }

                // 和系统音乐一样压暗背景：作者名的叠加提亮是“背景 + 约 117”，
                // 背景太亮会直接加成纯白，和标题分不出层次；文字整体对比度也更好。
                if !isUnderlay || image != nil {
                    Color.black.opacity(Self.dimming)
                }
            }
            .frame(width: proxy.size.width, height: proxy.size.height)
            .clipped()
            // 在铺满安全区之后的里层量：外层量到的是不含安全区的框，副本会按错的大小画，
            // 和真背景错开，列表顶部的渐隐带里就会显出一道印子。
            .onGeometryChange(for: CGRect.self) {
                $0.frame(in: .named(NowPlayingContentCoordinateSpace.name))
            } action: {
                onFrameChange?($0)
            }
        }
        .ignoresSafeArea(edges: ignoresSafeArea ? .all : [])
        .accessibilityHidden(true)
        .task(id: artworkURL) {
            guard let request = Self.request(for: artworkURL) else {
                image = nil
                return
            }
            guard let loaded = try? await ImagePipeline.shared.image(for: request),
                  !Task.isCancelled, loaded !== image else { return }
            // 只有换歌（已经有旧封面）时才交叉淡入；第一次出现直接显示。
            let animates = image != nil && !accessibilityReduceMotion
            withAnimation(animates ? .easeInOut(duration: 0.6) : nil) {
                image = loaded
            }
        }
    }
}
