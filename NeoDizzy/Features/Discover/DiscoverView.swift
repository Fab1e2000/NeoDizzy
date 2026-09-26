import SwiftUI

/// 发现页的分段，与网站首页的五个标签一致。
enum DiscoverSection: String, CaseIterable, Identifiable {
    case album, ep, dig, packs, deals

    var id: String { rawValue }

    var title: String {
        switch self {
        case .album: DiscCategory.album.title
        case .ep: DiscCategory.ep.title
        case .dig: DiscCategory.dig.title
        case .packs: "pack"
        case .deals: String(localized: "限时优惠")
        }
    }

    var category: DiscCategory? {
        switch self {
        case .album: .album
        case .ep: .ep
        case .dig: .dig
        case .packs, .deals: nil
        }
    }
}

@Observable
final class DiscoverModel {
    var section: DiscoverSection = .album

    /// 每个分段各自保留列表和滚动进度，来回切换不重新加载。
    let lists: [DiscCategory: PagedList<DiscSummary>] = Dictionary(
        uniqueKeysWithValues: DiscCategory.allCases.map { category in
            (category, PagedList { page in try await DizzyAPI.shared.discs(category, page: page) })
        }
    )
    /// 首页 HTML 里的限时优惠和 pack，一次请求同时拿到。
    private(set) var showcase = Loadable { try await DizzyPages.shared.home() }

    func refresh() async {
        if let category = section.category {
            await lists[category]?.reload()
        } else {
            showcase = Loadable { try await DizzyPages.shared.home() }
            await showcase.load()
        }
    }
}

struct DiscoverView: View {
    @State private var model = DiscoverModel()

    var body: some View {
        MainTabPage(tab: .discover, onRefresh: { await model.refresh() }) {
            HStack(spacing: 12) {
                NavigationLink(value: AppRoute.shuffle) { Label("随便听听", systemImage: "shuffle").frame(maxWidth: .infinity) }
                NavigationLink(value: AppRoute.rank) { Label("支持者榜", systemImage: "trophy").frame(maxWidth: .infinity) }
            }.buttonStyle(.bordered).controlSize(.large)
            DiscoverSectionPicker(selection: $model.section)
            if let category = model.section.category, let list = model.lists[category] {
                PagedContent(list: list, webURL: DizzyURL.site) { discs in
                    DiscGrid(discs: discs)
                }
            } else {
                LoadableContent(state: model.showcase, webURL: DizzyURL.site) { showcase in
                    if model.section == .packs {
                        LazyVGrid(columns: DizzyGrid.columns, alignment: .leading, spacing: 22) {
                            ForEach(showcase.packs) { PackCard(pack: $0) }
                        }
                    } else if showcase.deals.isEmpty {
                        Text("现在没有限时优惠。")
                            .font(.subheadline)
                            .foregroundStyle(DizzyPalette.mutedText)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 60)
                    } else {
                        LazyVGrid(columns: DizzyGrid.columns, alignment: .leading, spacing: 22) {
                            ForEach(showcase.deals) { deal in
                                NavigationLink(value: AppRoute.disc(id: deal.disc.id)) {
                                    DiscCard(disc: deal.disc, caption: deal.deadline)
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }
                }
            }
        }
    }
}

/// 分段按钮，一行放不下时可以横向滑动。
private struct DiscoverSectionPicker: View {
    @Binding var selection: DiscoverSection

    var body: some View {
        ScrollView(.horizontal) {
            HStack(spacing: 8) {
                ForEach(DiscoverSection.allCases) { section in
                    let isSelected = section == selection
                    Button {
                        selection = section
                    } label: {
                        Text(section.title)
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(isSelected ? DizzyPalette.background : DizzyPalette.text)
                            .padding(.horizontal, 14)
                            .padding(.vertical, 8)
                            .background(isSelected ? DizzyPalette.accent : DizzyPalette.surface, in: .capsule)
                    }
                    .buttonStyle(.plain)
                    .accessibilityAddTraits(isSelected ? .isSelected : [])
                }
            }
        }
        .scrollIndicators(.hidden)
        .scrollClipDisabled()
    }
}
