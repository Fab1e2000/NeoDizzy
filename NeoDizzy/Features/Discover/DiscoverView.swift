import SwiftUI

struct DiscoverView: View {
    var body: some View {
        MainTabPage(tab: .discover) {
            HStack(spacing: 12) {
                DiscoverShortcut(route: .rank, systemImage: "chart.bar.fill")
                DiscoverShortcut(route: .shuffle, systemImage: "shuffle")
            }
            PlaceholderCard(
                systemImage: "square.stack.3d.up.fill",
                title: "专辑浏览",
                message: "数字专辑、单曲 EP、下载商品和限时优惠会显示在这里。"
            )
        }
    }
}

/// 发现页顶部的快捷入口。
private struct DiscoverShortcut: View {
    let route: AppRoute
    let systemImage: String

    var body: some View {
        NavigationLink(value: route) {
            Label(route.title, systemImage: systemImage)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(DizzyPalette.text)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 14)
                .background(DizzyPalette.surface, in: .rect(cornerRadius: 14))
        }
        .buttonStyle(.plain)
    }
}
