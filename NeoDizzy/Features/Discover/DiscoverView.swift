import SwiftUI

struct DiscoverView: View {
    @State private var model = DiscoverModel()
    @State private var search = SearchModel()

    var body: some View {
        MainTabPage(tab: .discover, onRefresh: {
            if let discs = search.discs { await discs.reload() }
            else { await model.refresh() }
        }) {
            DiscoverSearchBar(text: $search.query) { search.submit() }
            if search.keyword != nil {
                DiscoverSearchResults(model: search)
                    .id(search.keyword)
            } else {
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
        .scrollDismissesKeyboard(.interactively)
        .onChange(of: search.query) { _, query in
            if query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { search.clear() }
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
