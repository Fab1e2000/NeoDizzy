import SwiftUI

/// DizzyLab 的透明 PNG 头像使用原图，CDN 的 !cover 会将其转为白底 JPEG。
/// 来源 URL 处理保留在平台边界，通用头像不认识任何平台。
struct DizzyLabAvatarImage: View {
    let url: URL?
    var size: CGFloat? = 36

    var body: some View {
        AvatarImage(url: DizzyURL.avatar(url), size: size)
    }
}
