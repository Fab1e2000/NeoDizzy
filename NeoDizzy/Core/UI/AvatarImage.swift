import SwiftUI

/// 圆角方形头像（社团、用户），iOS 与 Mac 共用；nil 尺寸时随父视图布局。
/// 平台在传入前规范化图片地址；组件只负责显示。
struct AvatarImage: View {
    let url: URL?
    var size: CGFloat? = 36

    var body: some View {
        ArtworkImage(url: url, cornerRadius: 0, contentMode: .fit)
            .frame(width: size, height: size)
            .background(Color(white: 0.45))
            .clipShape(.rect(cornerRadius: min((size ?? 60) * 0.2, 16)))
    }
}
