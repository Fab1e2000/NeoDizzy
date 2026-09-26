import SwiftUI

/// 推入页面的总入口。各页面接入数据前先显示占位内容。
struct AppRouteDestination: View {
    let route: AppRoute

    var body: some View {
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
