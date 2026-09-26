import SwiftUI

struct LabelsView: View {
    var body: some View {
        MainTabPage(tab: .labels) {
            PlaceholderCard(
                systemImage: "bookmark.fill",
                title: "社团列表",
                message: "DizzyLab 上的全部社团和厂牌会显示在这里。"
            )
        }
    }
}
