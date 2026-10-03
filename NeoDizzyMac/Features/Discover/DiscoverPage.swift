import SwiftUI

/// 发现：工具栏中间的分段控件切换数字专辑、单曲 EP、下载商品、pack 和限时优惠，与网站首页一致。
struct DiscoverPage: View {
    @Environment(MacAppModel.self) private var model

    var body: some View {
        @Bindable var discover = model.discover
        PageScroll(title: String(localized: "发现")) {
            if let category = discover.section.category, let list = discover.lists[category] {
                PagedSection(list: list, webURL: DizzyURL.site) { discs in
                    DiscGrid(discs: discs)
                }
            } else {
                LoadablePage(state: discover.showcase, webURL: DizzyURL.site) { showcase in
                    if discover.section == .packs {
                        LazyVGrid(columns: PageMetrics.gridColumns, alignment: .leading, spacing: PageMetrics.gridSpacing) {
                            ForEach(showcase.packs) { PackCard(pack: $0) }
                        }
                    } else if showcase.deals.isEmpty {
                        ContentUnavailableView("现在没有限时优惠", systemImage: "tag")
                            .padding(.vertical, 40)
                    } else {
                        LazyVGrid(columns: PageMetrics.gridColumns, alignment: .leading, spacing: PageMetrics.gridSpacing) {
                            ForEach(showcase.deals) { deal in
                                DiscCard(disc: deal.disc, caption: deal.deadline)
                            }
                        }
                    }
                }
            }
        }
        .id(discover.section)
        .toolbar {
            ToolbarItem(placement: .principal) {
                Picker("分类", selection: $discover.section) {
                    ForEach(DiscoverSection.allCases) { Text($0.title).tag($0) }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
            }
        }
        .pageRefresh { await discover.refresh() }
    }
}
