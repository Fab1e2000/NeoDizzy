import SwiftUI

/// 歌手、社团页的头部：大头像（歌手为圆形，社团为圆角方形）、名字和一行说明，下面是操作按钮。
/// 放在 `AlbumDetailScrollView` 里，背景取头像的颜色，和专辑页是同一套外观。
struct ProfileHero<Actions: View>: View {
    let artworkURL: URL?
    let title: String
    let subtitle: String
    var cornerRadius: CGFloat = 1_000
    @ViewBuilder var actions: () -> Actions

    var body: some View {
        VStack(spacing: 10) {
            ArtworkImage(url: artworkURL, cornerRadius: cornerRadius)
                .frame(width: 168, height: 168)
                .shadow(color: .black.opacity(0.25), radius: 18, y: 10)
            Text(title)
                .font(.title.weight(.heavy))
                .multilineTextAlignment(.center)
                .lineLimit(2)
                .padding(.top, 6)
            if !subtitle.isEmpty {
                Text(subtitle)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .lineLimit(2)
            }
            actions().padding(.top, 8)
        }
        .frame(maxWidth: .infinity)
        .padding(.horizontal, 20)
        .padding(.top, 12)
    }
}

/// 歌手、社团页里一块内容的标题，右侧可选「全部」。
struct ProfileSectionHeader<All: View>: View {
    let title: String
    var allTitle: String? = nil
    @ViewBuilder var all: () -> All

    var body: some View {
        HStack(alignment: .firstTextBaseline) {
            Text(title).font(.title3.bold()).accessibilityAddTraits(.isHeader)
            Spacer()
            if let allTitle {
                // 走导航路径：在「全部」页里再点进详情时只推入一页。
                NavigationLink(allTitle, value: AppRoute.page(allTitle, all)).font(.subheadline)
            }
        }
        .padding(.horizontal, 20)
    }
}

extension ProfileSectionHeader where All == EmptyView {
    init(title: String) { self.init(title: title, allTitle: nil) { EmptyView() } }
}
