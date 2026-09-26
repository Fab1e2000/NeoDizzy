import SwiftUI

struct SearchView: View {
    @State private var query = ""

    var body: some View {
        ScrollView {
            if !query.trimmingCharacters(in: .whitespaces).isEmpty {
                PlaceholderCard(
                    systemImage: "magnifyingglass",
                    title: "搜索结果",
                    message: "专辑和社团的搜索结果会显示在这里。"
                )
                .padding(20)
            }
        }
        .dizzyPageBackground()
        .toolbar(.hidden, for: .navigationBar)
        .searchable(text: $query, prompt: "搜索专辑、社团")
    }
}
