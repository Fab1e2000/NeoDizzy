import SwiftUI

struct DiscoverView: View {
    @Environment(DizzyLabContentCache.self) private var contentCache
    @Environment(AccountStore.self) private var account
    private var model: DiscoverModel { contentCache.discover }
    @State private var search = SearchModel()

    var body: some View {
        @Bindable var model = model
        MainTabPage(title: "DizzyLab", onRefresh: {
            if let discs = search.discs { await discs.reload(keepingItems: true) }
            else { await model.refresh() }
        }) {
            DiscoverSearchBar(text: $search.query) { search.submit() }
            if search.keyword != nil {
                DiscoverSearchResults(model: search)
                    .id(search.keyword)
            } else {
                DizzyLabShortcuts()
                DiscoveryCategoryPicker(selection: $model.section, options: DiscoverSection.allCases.map { ($0, $0.title) })
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
        .task { contentCache.prewarm(account: account) }
        .scrollDismissesKeyboard(.interactively)
        .onChange(of: search.query) { _, query in
            if query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { search.clear() }
        }
    }
}

/// 分段按钮，一行放不下时可以横向滑动。
struct DiscoveryCategoryPicker<Selection: Hashable>: View {
    @Binding var selection: Selection
    let options: [(Selection, String)]

    var body: some View {
        ScrollView(.horizontal) {
            HStack(spacing: 8) {
                ForEach(options, id: \.0) { option in
                    let isSelected = option.0 == selection
                    Button {
                        selection = option.0
                    } label: {
                        Text(option.1)
                            .font(.subheadline.weight(isSelected ? .semibold : .medium))
                            .foregroundStyle(isSelected ? DizzyPalette.accent : Color.secondary)
                            .padding(.horizontal, 14)
                            .padding(.vertical, 10)
                            .frame(minHeight: 44)
                            .background(isSelected ? DizzyPalette.accent.opacity(0.12) : Color.clear, in: .capsule)
                            .contentShape(.capsule)
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
