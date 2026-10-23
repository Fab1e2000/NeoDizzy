import SwiftUI

/// 模块内页面使用系统标题和返回按钮，不再重复顶层页头和头像入口。
struct DizzyLabPage<Content: View>: View {
    let section: DizzyLabSection
    var onRefresh: (() async -> Void)?
    @ViewBuilder var content: Content

    var body: some View {
        let page = ScrollView {
            LazyVStack(alignment: .leading, spacing: 20) { content }
                .padding(.horizontal, 20)
                .padding(.vertical, 24)
        }
        .dizzyPageBackground()
        .navigationTitle(section.title)
        .navigationBarTitleDisplayMode(.large)
        .toolbar(.visible, for: .navigationBar)
        .toolbarBackground(.automatic, for: .navigationBar)

        if let onRefresh { page.refreshable { await onRefresh() } }
        else { page }
    }
}

