import SwiftUI

@Observable
final class SearchModel {
    var query = ""
    private(set) var keyword: String?
    /// 社团只在第一页结果里。
    private(set) var users: [CommunityUser] = []
    private(set) var labels: [SearchLabel] = []
    private(set) var discs: PagedList<SearchDisc>?

    /// 只在按下搜索键时请求，不跟随每次输入。
    func submit() {
        let keyword = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !keyword.isEmpty, keyword != self.keyword else { return }
        self.keyword = keyword
        labels = []
        users = []
        discs = PagedList { [weak self] page in
            let results = try await DizzyPages.shared.search(keyword, page: page)
            if page == 1, self?.keyword == keyword { self?.labels = results.labels; self?.users = results.users }
            return Page(items: results.discs, hasMore: results.hasMore)
        }
    }

    func clear() {
        keyword = nil
        labels = []
        users = []
        discs = nil
    }
}

/// 搜索页：标题和搜索框共同遵循标题栏的固定 / 滚动设置。
/// 不用系统的 `.searchable`：它的搜索框放在导航栏里，而主页面都隐藏了导航栏，搜索框会跟着消失。
struct SearchView: View {
    @State private var model = SearchModel()
    @FocusState private var isSearchFieldFocused: Bool

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 16) {
                ScrollingPageHeaderRow { searchHeader }
                if let keyword = model.keyword, let discs = model.discs {
                    if !model.labels.isEmpty {
                        SectionHeading(title: "社团")
                        ForEach(model.labels) { label in
                            NavigationLink(value: AppRoute.label(name: label.name)) {
                                SearchResultRow(
                                    coverURL: label.coverURL,
                                    title: label.name,
                                    subtitle: nil,
                                    excerpt: label.description
                                )
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    if !model.users.isEmpty {
                        SectionHeading(title: "用户")
                        ForEach(model.users) { CommunityUserLink(user: $0) }
                    }
                    SectionHeading(title: "作品")
                    PagedContent(list: discs, webURL: DizzyURL.search(keyword), emptyMessage: "没有找到相关作品。") { results in
                        ForEach(results) { result in
                            NavigationLink(value: AppRoute.disc(id: result.disc.id)) {
                                SearchResultRow(
                                    coverURL: result.disc.coverURL,
                                    title: result.disc.title,
                                    subtitle: result.disc.labelName,
                                    excerpt: result.excerpt
                                )
                            }
                            .buttonStyle(.plain)
                        }
                    }
                } else {
                    Text("以专辑名称、专辑编号、社团或音乐人为关键字搜索。")
                        .font(.subheadline)
                        .foregroundStyle(DizzyPalette.mutedText)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 60)
                }
            }
            .padding(.horizontal, 20)
            .padding(.top, 8)
            .padding(.bottom, 24)
        }
        .scrollDismissesKeyboard(.immediately)
        .pageHeaderPlacement { searchHeader }
        .dizzyPageBackground()
        .toolbar(.hidden, for: .navigationBar)
        .onChange(of: model.query) { _, query in
            if query.isEmpty { model.clear() }
        }
        .task {
            // 第一次进入搜索页时直接弹出键盘。
            if model.keyword == nil, model.query.isEmpty {
                isSearchFieldFocused = true
            }
        }
    }

    private var searchHeader: some View {
        VStack(spacing: 4) {
            PageHeader(title: MainTab.search.title)
            SearchField(text: $model.query, isFocused: $isSearchFieldFocused) {
                model.submit()
            }
        }.padding(.bottom, 8)
    }

}

/// 搜索框：按键盘上的「搜索」提交，右侧可以一键清空。
private struct SearchField: View {
    @Binding var text: String
    var isFocused: FocusState<Bool>.Binding
    let onSubmit: () -> Void

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(DizzyPalette.mutedText)
            TextField("搜索专辑、社团、用户", text: $text)
                .focused(isFocused)
                .submitLabel(.search)
                .onSubmit(onSubmit)
                .autocorrectionDisabled()
                .textInputAutocapitalization(.never)
                .foregroundStyle(DizzyPalette.text)
            if !text.isEmpty {
                Button {
                    text = ""
                    isFocused.wrappedValue = true
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(DizzyPalette.mutedText)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("清除")
            }
        }
        .padding(.horizontal, 14)
        .frame(height: 44)
        .background(DizzyPalette.surface, in: .capsule)
    }
}

/// 搜索结果的一行：封面、标题、社团和一段介绍。
private struct SearchResultRow: View {
    let coverURL: URL?
    let title: String
    let subtitle: String?
    let excerpt: String

    var body: some View {
        HStack(alignment: .top, spacing: 14) {
            ArtworkImage(url: coverURL, cornerRadius: 10)
                .frame(width: 72)
            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.headline)
                    .foregroundStyle(DizzyPalette.text)
                    .lineLimit(2)
                if let subtitle, !subtitle.isEmpty {
                    Text(subtitle)
                        .font(.subheadline)
                        .foregroundStyle(DizzyPalette.accent)
                        .lineLimit(1)
                }
                if !excerpt.isEmpty {
                    Text(excerpt)
                        .font(.caption)
                        .foregroundStyle(DizzyPalette.mutedText)
                        .lineLimit(2)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .contentShape(.rect)
    }
}
