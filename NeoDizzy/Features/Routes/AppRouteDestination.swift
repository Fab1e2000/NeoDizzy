import SwiftUI

/// 推入页面的总入口。用户主页、排行榜、随便听听在 M5 接入，先显示占位内容。
struct AppRouteDestination: View {
    let route: AppRoute

    var body: some View {
        switch route {
        case .disc(let id):
            DiscDetailView(id: id)
        case .label(let name):
            LabelDetailView(name: name)
        case .tag(let tag):
            TagDiscsView(tag: tag)
        case .pack(let id):
            PackDetailView(id: id)
        case .user, .rank, .shuffle:
            placeholder
        }
    }

    private var placeholder: some View {
        ScrollView {
            PlaceholderCard(systemImage: systemImage, title: "即将推出", message: "这个页面还在开发中。")
                .padding(20)
        }
        .dizzyPageBackground()
        .navigationTitle(route.title)
        .navigationBarTitleDisplayMode(.inline)
    }

    private var systemImage: String {
        switch route {
        case .disc: "opticaldisc.fill"
        case .label: "bookmark.fill"
        case .user: "person.fill"
        case .tag: "number"
        case .pack: "shippingbox.fill"
        case .rank: "chart.bar.fill"
        case .shuffle: "shuffle"
        }
    }
}
