import SwiftUI

struct DiscoverView: View {
    @Environment(DizzyLabContentCache.self) private var contentCache
    @Environment(AccountStore.self) private var account
    private var model: DiscoverModel { contentCache.discover }

    var body: some View {
        @Bindable var model = model
        MainTabPage(title: "DizzyLab", onRefresh: { await model.refresh() }) {
            Group {
                DizzyLabShortcuts()
                DiscoveryCategoryPicker(selection: $model.section, options: DiscoverSection.allCases.map { ($0, $0.title) })
                if let category = model.section.category, let list = model.lists[category] {
                    PagedContent(list: list) { discs in
                        DiscGrid(discs: discs)
                    }
                } else {
                    LoadableContent(state: model.showcase) { showcase in
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
                            .font(.subheadline.weight(isSelected ? .semibold : .regular))
                            .foregroundStyle(isSelected ? DizzyPalette.background : DizzyPalette.text)
                            .padding(.horizontal, 14)
                            .frame(minHeight: 34)
                            .background(isSelected ? DizzyPalette.text : DizzyPalette.surface, in: .capsule)
                            .frame(minHeight: 44)
                            .contentShape(.rect)
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
