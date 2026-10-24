import SwiftUI

struct DiscoverSearchResults: View {
    let model: SearchModel
    @Environment(DizzyLabContentCache.self) private var contentCache
    var body: some View {
        if model.keyword != nil, let discs = model.discs {
            if !model.labels.isEmpty {
                SectionHeading(title: "社团")
                ForEach(model.labels) { label in
                    NavigationLink(value: AppRoute.label(name: label.name)) {
                        SearchResultRow(
                            coverURL: label.coverURL,
                            isAvatar: true,
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
            PagedContent(list: discs, emptyMessage: "没有找到相关作品。") { results in
                ForEach(results) { result in
                    AlbumNavigationLink(value: AppRoute.disc(id: result.disc.id), artworkURL: result.disc.coverURL) {
                        SearchResultRow(
                            coverURL: result.disc.coverURL,
                            title: result.disc.title,
                            subtitle: result.disc.labelName,
                            excerpt: result.excerpt
                        )
                        .prefetchAlbumArtwork(url: result.disc.coverURL)
                    }
                    .buttonStyle(.plain)
                    .onChange(of: result.disc, initial: true) { _, disc in contentCache.remember([disc]) }
                }
            }
        }
    }
}

/// 搜索结果的一行：封面、标题、社团和一段介绍。
private struct SearchResultRow: View {
    let coverURL: URL?
    /// 社团显示方形头像，作品显示封面。
    var isAvatar = false
    let title: String
    let subtitle: String?
    let excerpt: String

    var body: some View {
        HStack(alignment: .top, spacing: 14) {
            Group {
                if isAvatar {
                    DizzyLabAvatarImage(url: coverURL, size: 72)
                } else {
                    ArtworkImage(url: coverURL, cornerRadius: 10)
                        .frame(width: 72)
                }
            }
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

// Adapted from MeloX Features/Search/SearchView.swift (GPL-3.0).

/// 统一搜索里的「DizzyLab」一组：最多两个社团、三张作品。
struct DizzyLabSearchSection: View {
    let query: String
    @Environment(DizzyLabContentCache.self) private var contentCache
    @State private var model = SearchModel()

    var body: some View {
        let labels = Array(model.labels.prefix(2))
        let discs = Array((model.discs?.items ?? []).prefix(3))
        Group {
            if let list = model.discs, let failure = list.failure, list.items.isEmpty {
                SearchGroup(title: DizzyLabModule.metadata.title) {
                    SearchCardRow { SearchSectionFailure(title: "DizzyLab 搜索失败", message: failure) { await list.reload() } }
                }
            } else if let list = model.discs, list.items.isEmpty, list.isLoading || list.loadedPages == 0 {
                SearchGroup(title: DizzyLabModule.metadata.title) {
                    SearchCardRow { SearchSectionMessage(text: "正在搜索…", isLoading: true) }
                }
            } else if labels.isEmpty && discs.isEmpty {
                SearchGroup(title: DizzyLabModule.metadata.title) {
                    SearchCardRow { SearchSectionMessage(text: "DizzyLab 没有和「\(query)」相关的作品。") }
                }
            } else {
                SearchGroup(title: DizzyLabModule.metadata.title, allResults: .dizzyLabSearch(query)) {
                    ForEach(labels) { label in
                        NavigationLink(value: AppRoute.label(name: label.name)) {
                            SearchMediaRow(title: label.name, subtitle: "社团", artworkURL: label.coverURL, circular: true)
                        }
                        .buttonStyle(.plain)
                    }
                    ForEach(discs) { result in
                        AlbumNavigationLink(value: AppRoute.disc(id: result.disc.id), artworkURL: result.disc.coverURL) {
                            SearchMediaRow(title: result.disc.title, subtitle: result.disc.labelName, artworkURL: result.disc.coverURL)
                        }
                        .buttonStyle(.plain)
                        .onChange(of: result.disc, initial: true) { _, disc in contentCache.remember([disc]) }
                    }
                }
            }
        }
        .task(id: query) {
            model.query = query
            model.submit()
            if let discs = model.discs, discs.loadedPages == 0 { await discs.loadMore() }
        }
    }
}

/// 「查看全部」：照搬 MeloX 的搜索结果，普通列表依次是社团、用户和作品，滚到底继续加载。
struct DizzyLabSearchPage: View {
    let query: String
    @Environment(DizzyLabContentCache.self) private var contentCache
    @State private var model = SearchModel()

    var body: some View {
        let discs = model.discs
        List {
            if !model.labels.isEmpty {
                Section("社团") {
                    ForEach(model.labels) { label in
                        NavigationLink(value: AppRoute.label(name: label.name)) {
                            SearchMediaRow(title: label.name, subtitle: label.description, artworkURL: label.coverURL, circular: true,
                                           showsChevron: false)
                        }
                        .songListRow()
                    }
                }
                .listRowSeparator(.hidden)
                .listSectionSeparator(.hidden)
            }
            if !model.users.isEmpty {
                Section("用户") {
                    ForEach(model.users) { user in
                        NavigationLink(value: AppRoute.user(id: user.id)) {
                            SearchMediaRow(title: user.name, subtitle: nil, artworkURL: user.avatarURL, circular: true, showsChevron: false)
                        }
                        .songListRow()
                    }
                }
                .listRowSeparator(.hidden)
                .listSectionSeparator(.hidden)
            }
            if let discs, !discs.items.isEmpty {
                Section("作品") {
                    ForEach(discs.items) { result in
                        AlbumNavigationLink(value: AppRoute.disc(id: result.disc.id), artworkURL: result.disc.coverURL) {
                            SearchMediaRow(title: result.disc.title, subtitle: result.disc.labelName ?? result.excerpt,
                                           artworkURL: result.disc.coverURL, showsChevron: false)
                        }
                        .songListRow()
                        .onChange(of: result.disc, initial: true) { _, disc in contentCache.remember([disc]) }
                        .onAppear {
                            if result.id == discs.items.last?.id, discs.hasMore, !discs.isLoading { Task { await discs.loadMore() } }
                        }
                    }
                }
                .listRowSeparator(.hidden)
                .listSectionSeparator(.hidden)
            }
            if let discs, let failure = discs.failure {
                SearchSectionFailure(title: "DizzyLab 搜索失败", message: failure) {
                    await discs.loadMore()
                }
                .listRowSeparator(.hidden)
            } else if discs == nil || discs?.isLoading == true {
                HStack { Spacer(); ProgressView("正在搜索…"); Spacer() }.listRowSeparator(.hidden)
            } else if let discs, discs.isEmpty, model.labels.isEmpty, model.users.isEmpty {
                ContentUnavailableView.search(text: query).listRowSeparator(.hidden)
            }
        }
        .listStyle(.plain)
        .navigationTitle("DizzyLab · 「\(query)」")
        .navigationBarTitleDisplayMode(.inline)
        .task(id: query) {
            model.query = query
            model.submit()
            if let discs = model.discs, discs.loadedPages == 0 { await discs.loadMore() }
        }
    }
}
