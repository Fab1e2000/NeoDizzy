import SwiftUI

/// 方形头像（社团、用户），iOS 与 Mac 共用；nil 尺寸时随父视图布局。
/// 社团字标多是透明背景的 PNG：取原图而不是 CDN 的 `!cover`（会转成白底 JPEG），
/// 按 `.fit` 完整显示，下面垫中性灰底，白色和黑色字标都看得清。
struct AvatarImage: View {
    let url: URL?
    var size: CGFloat? = 36

    var body: some View {
        ArtworkImage(url: DizzyURL.avatar(url), cornerRadius: 0, contentMode: .fit)
            .frame(width: size, height: size)
            .background(Color(white: 0.45))
    }
}
