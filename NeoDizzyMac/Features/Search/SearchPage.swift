import SwiftUI

/// 搜索页：标题下方是与内容同宽的搜索框；还没搜索时显示最近搜索，搜索后依次是社团、用户与作品。只在按下回车时请求。
struct SearchPage: View {
    @Environment(MacAppModel.self) private var model
    @FocusState private var isFieldFocused: Bool

    private var search: SearchModel { model.search }

    var body: some View {
        PageScroll(title: String(localized: "搜索")) {
            VStack(alignment: .leading, spacing: 10) {
                SearchField(isFocused: $isFieldFocused)
                if let keyword = search.keyword {
                    Text("“\(keyword)”的搜索结果")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }
            }
            if let keyword = search.keyword, let discs = search.discs {
                if !search.labels.isEmpty {
                    VStack(alignment: .leading, spacing: 12) {
                        SectionTitle(String(localized: "社团"))
                        LazyVGrid(columns: PageMetrics.rowColumns, alignment: .leading, spacing: 12) {
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
            } else if !model.recentSearches.isEmpty {
                RecentSearches { keyword in
                    model.search.query = keyword
                    model.submitSearch()
                }
            } else {
                ContentUnavailableView {
                    Label("搜索 DizzyLab", systemImage: "magnifyingglass")
                } description: {
                    Text("输入专辑、社团或用户名称，按回车键搜索。")
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 60)
            }
        }
        .pageRefresh { await model.search.discs?.reload() }
        .onChange(of: search.query) { _, query in
            if query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { search.clear() }
        }
        // 进入页面时还没有搜索过、或从菜单按下 ⌘F，都直接把光标放进搜索框。
        .onChange(of: model.isSearchFocused, initial: true) { _, focused in
            guard focused || search.keyword == nil else { return }
            // 等页面挂载后再聚焦，也消费窗口创建前的 ⌘F 请求。
            DispatchQueue.main.async {
                isFieldFocused = true
                model.isSearchFocused = false
            }
        }
    }
}

/// 搜索页顶部的大号搜索框。
private struct SearchField: View {
    var isFocused: FocusState<Bool>.Binding
    @Environment(MacAppModel.self) private var model

    var body: some View {
        @Bindable var search = model.search
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 15, weight: .medium))
                .foregroundStyle(.secondary)
            TextField("专辑、社团或用户", text: $search.query)
                .textFieldStyle(.plain)
                .font(.system(size: 15))
                .focused(isFocused)
                .onSubmit { model.submitSearch() }
                .accessibilityLabel("搜索专辑、社团或用户")
            if !search.query.isEmpty {
                Button {
                    search.query = ""
                    isFocused.wrappedValue = true
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .help("清除搜索")
            }
        }
        .padding(.horizontal, 14)
        .frame(height: 40)
        .background(.primary.opacity(0.07), in: .rect(cornerRadius: 10))
        .overlay {
            RoundedRectangle(cornerRadius: 10)
                .strokeBorder(isFocused.wrappedValue ? Color.dizzyAccent.opacity(0.6) : .primary.opacity(0.08), lineWidth: 1)
        }
    }
}

/// 最近搜索的关键词，点击重新搜索。
private struct RecentSearches: View {
    let select: (String) -> Void
    @Environment(MacAppModel.self) private var model

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionTitle(String(localized: "最近搜索")) {
                Button("清除") { model.clearRecentSearches() }
                    .buttonStyle(.plain)
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
            FlowLayout(spacing: 8) {
                ForEach(model.recentSearches, id: \.self) { keyword in
                    Button { select(keyword) } label: {
                        Label(keyword, systemImage: "clock.arrow.circlepath")
                            .font(.callout)
                            .padding(.horizontal, 12)
                            .frame(height: 28)
                            .background(.primary.opacity(0.07), in: Capsule())
                            .contentShape(Capsule())
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }
}
