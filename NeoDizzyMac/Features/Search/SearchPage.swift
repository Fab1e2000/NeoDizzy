import SwiftUI

/// 搜索结果：社团、用户与作品。只在侧边栏搜索框按下回车时请求。
struct SearchPage: View {
    @Environment(MacAppModel.self) private var model

    private var search: SearchModel { model.search }

    var body: some View {
        PageScroll(title: search.keyword.map { "“\($0)”" } ?? String(localized: "搜索"),
                   subtitle: search.keyword == nil ? nil : String(localized: "搜索结果")) {
            if let keyword = search.keyword, let discs = search.discs {
                if !search.labels.isEmpty {
                    VStack(alignment: .leading, spacing: 12) {
                        SectionTitle(String(localized: "社团"))
                        LazyVGrid(columns: [GridItem(.adaptive(minimum: 320), spacing: 14)], alignment: .leading, spacing: 12) {
                            ForEach(search.labels) { label in
                                LabelRow(name: label.name, coverURL: label.coverURL, description: label.description)
                            }
                        }
                    }
                }
                if !search.users.isEmpty {
                    VStack(alignment: .leading, spacing: 12) {
                        SectionTitle(String(localized: "用户"))
                        ScrollView(.horizontal) {
                            HStack(alignment: .top, spacing: 18) {
                                ForEach(search.users) { UserChip(user: $0) }
                            }
                        }
                        .scrollIndicators(.never)
                    }
                }
                VStack(alignment: .leading, spacing: 12) {
                    SectionTitle(String(localized: "作品"))
                    PagedSection(list: discs, webURL: DizzyURL.search(keyword), emptyTitle: "没有找到相关作品",
                                 emptySystemImage: "magnifyingglass") { results in
                        LazyVGrid(columns: PageMetrics.gridColumns, alignment: .leading, spacing: PageMetrics.gridSpacing) {
                            ForEach(results) { result in
                                DiscCard(disc: result.disc, caption: result.excerpt)
                            }
                        }
                    }
                }
                .id(keyword)
            } else {
                ContentUnavailableView {
                    Label("搜索 DizzyLab", systemImage: "magnifyingglass")
                } description: {
                    Text("在侧边栏的搜索框输入专辑、社团或用户名称，按回车键搜索。")
                } actions: {
                    Button("开始搜索") { model.isSearchFocused = true }
                }
                .padding(.vertical, 60)
            }
        }
        .pageRefresh { await model.search.discs?.reload() }
    }
}
