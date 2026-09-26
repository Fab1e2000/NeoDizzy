import SwiftUI

struct FeedView: View {
    var body: some View {
        MainTabPage(tab: .feed) {
            PlaceholderCard(
                systemImage: "newspaper.fill",
                title: "关注的社团",
                message: "登录后，你关注的社团发布的新作会显示在这里。"
            )
        }
    }
}
