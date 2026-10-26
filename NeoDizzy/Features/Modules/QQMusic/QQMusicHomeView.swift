import SwiftUI

struct QQMusicHomeView: View {
    @Environment(QQMusicStore.self) private var store
    @Environment(QQMusicContentCache.self) private var cache
    @State private var refreshCompletion = 0
    private var recommendations: QQMusicPageModel { cache.page(.recommended, revision: store.revision) }
    private var charts: QQMusicPageModel { cache.page(.charts, revision: store.revision) }

    var body: some View {
        MainTabPage(title: "QQ 音乐", onRefresh: {
            await load(refresh: true)
            guard !Task.isCancelled else { return }
            refreshCompletion += 1
        }) {
            QQMusicDiscoveryShortcuts()
            VStack(alignment: .leading, spacing: 14) {
                QQMusicSectionLink(title: "推荐播放列表", route: .recommended)
                if !recommendations.playlists.isEmpty {
                    QQMusicCoverShelf(collections: Array(recommendations.playlists.prefix(8)))
                }
                QQMusicShelfStatus(model: recommendations, isEmpty: recommendations.playlists.isEmpty) {
                    await recommendations.load(store: store, route: .recommended)
                }
            }
            VStack(alignment: .leading, spacing: 14) {
                QQMusicSectionLink(title: "排行榜", route: .charts)
                if !charts.charts.isEmpty {
                    QQMusicCoverShelf(collections: Array(charts.charts.prefix(8)), isChart: true)
                }
                QQMusicShelfStatus(model: charts, isEmpty: charts.charts.isEmpty) {
                    await charts.load(store: store, route: .charts)
                }
            }
        }
        .modifier(QQMusicHomeRefreshRecovery(completion: refreshCompletion))
        .task(id: store.revision) { await load() }
    }

    private func load(refresh: Bool = false) async {
        async let recommended: Void = load(recommendations, route: .recommended, refresh: refresh)
        async let ranked: Void = load(charts, route: .charts, refresh: refresh)
        _ = await (recommended, ranked)
    }

    private func load(_ model: QQMusicPageModel, route: QQMusicRoute, refresh: Bool) async {
        if refresh || !model.hasLoaded { await model.load(store: store, route: route) }
    }
}

/// QQ 首页的多个分区异步更新后，收起可能残留的下拉空隙。
/// 只修正顶部区域，不打断等待刷新时已经滚入正文的用户。
struct QQMusicHomeRefreshRecovery: ViewModifier {
    let completion: Int
    @State private var position = ScrollPosition(edge: .top)
    @State private var isAtTop = true
    @State private var isInteracting = false

    func body(content: Content) -> some View {
        content
            .scrollPosition($position)
            .onScrollGeometryChange(for: Bool.self) { geometry in
                geometry.contentOffset.y + geometry.contentInsets.top <= 1
            } action: { _, atTop in
                isAtTop = atTop
            }
            .onScrollPhaseChange { _, phase in
                isInteracting = phase == .tracking || phase == .interacting
            }
            .onChange(of: completion) { _, _ in
                guard isAtTop, !isInteracting else { return }
                withAnimation(.easeOut(duration: 0.25)) {
                    position.scrollTo(edge: .top)
                }
            }
    }
}

private struct QQMusicSectionLink: View {
    let title: String
    let route: QQMusicRoute

    var body: some View {
        NavigationLink(value: AppRoute.qqmusic(route)) {
            HStack {
                Text(title).font(.title2.bold())
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.subheadline.weight(.semibold)).foregroundStyle(.secondary)
            }
            .foregroundStyle(.primary)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("查看全部\(title)")
    }
}

private struct QQMusicCoverShelf: View {
    let collections: [QQMusicCollection]
    var isChart = false
    @Environment(\.dynamicTypeSize) private var typeSize

    var body: some View {
        ScrollView(.horizontal) {
            LazyHStack(alignment: .top, spacing: 14) {
                ForEach(collections) { collection in
                    QQMusicCollectionCard(collection: collection, isChart: isChart, reservesTitleLines: true)
                        .frame(width: typeSize.isAccessibilitySize ? 220 : 156)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
        .scrollIndicators(.hidden)
        .contentMargins(.horizontal, 20, for: .scrollContent)
        .padding(.horizontal, -20)
    }
}

private struct QQMusicCollectionCard: View {
    let collection: QQMusicCollection
    var isChart = false
    var reservesTitleLines = false

    var body: some View {
        AlbumNavigationLink(value: AppRoute.qqmusic(isChart ? .chart(collection.id) : .playlist(collection.id)),
                            artworkURL: collection.coverURL) {
            CoverCard(title: collection.title, artworkURL: collection.coverURL, reservesTitleLines: reservesTitleLines)
        }.buttonStyle(.plain)
    }
}

private struct QQMusicShelfStatus: View {
    let model: QQMusicPageModel
    let isEmpty: Bool
    let retry: () async -> Void

    var body: some View {
        if let error = model.error {
            HStack {
                Text(error).font(.footnote).foregroundStyle(.secondary)
                Spacer()
                Button("重试") { Task { await retry() } }
            }
        } else if isEmpty && (!model.hasLoaded || model.loading) {
            QQMusicShelfSkeleton()
        } else if isEmpty {
            Text("暂无内容").font(.subheadline).foregroundStyle(.secondary)
        }
    }
}

private struct QQMusicShelfSkeleton: View {
    @Environment(\.dynamicTypeSize) private var typeSize

    var body: some View {
        ScrollView(.horizontal) {
            HStack(alignment: .top, spacing: 14) {
                ForEach(0..<4) { _ in
                    VStack(alignment: .leading, spacing: 6) {
                        RoundedRectangle(cornerRadius: 10)
                            .fill(.gray.opacity(0.18)).aspectRatio(1, contentMode: .fit)
                        Text("音乐与故事\n等待与你相遇")
                            .font(.subheadline.weight(.semibold)).lineLimit(2)
                            .redacted(reason: .placeholder)
                    }.frame(width: typeSize.isAccessibilitySize ? 220 : 156)
                }
            }
        }
        .scrollIndicators(.hidden)
        .contentMargins(.horizontal, 20, for: .scrollContent)
        .padding(.horizontal, -20)
        .allowsHitTesting(false)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("正在加载内容")
    }
}

struct QQMusicBrowseView: View {
    let route: QQMusicRoute
    @Environment(QQMusicStore.self) private var store
    @Environment(QQMusicContentCache.self) private var cache
    private var sourceRoute: QQMusicRoute { if case .chartGroup = route { .charts } else { route } }
    private var model: QQMusicPageModel { cache.page(sourceRoute, revision: store.revision) }
    private var selectedGroup: QQMusicChartGroup? {
        guard case .chartGroup(let id) = route else { return nil }
        return model.chartGroups.first { $0.id == id }
    }
    private var title: String { selectedGroup?.title ?? (model.title.isEmpty ? route.title : model.title) }
    private var isRecommended: Bool { route == .recommended }
    private var isEmpty: Bool {
        if case .chartGroup = route { return selectedGroup?.charts.isEmpty ?? true }
        return model.playlists.isEmpty && model.charts.isEmpty
    }

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 20) {
                if isRecommended {
                    grid(model.playlists)
                } else if route == .charts {
                    ForEach(model.chartGroups) { group in
                        VStack(alignment: .leading, spacing: 14) {
                            Text(group.title).font(.title2.bold()).accessibilityAddTraits(.isHeader)
                            grid(group.charts)
                        }
                    }
                } else {
                    grid(selectedGroup?.charts ?? [])
                }
                if let error = model.error {
                    LoadFailureView(message: error) { await load(append: model.retryAppend) }
                } else if isEmpty && (!model.hasLoaded || model.loading) || model.loading && model.retryAppend {
                    ContentSkeleton(layout: .grid)
                } else if isEmpty {
                    ContentUnavailableView("暂无内容", systemImage: "music.note.list")
                }
                if model.more && model.error == nil && !model.loading {
                    AutoLoadMoreFooter(progress: model.playlists.count, load: { await load(append: true) }) {
                        ContentSkeleton(layout: .grid)
                    }
                }
            }.padding(20)
        }
        .dizzyPageBackground()
        .navigationTitle(title)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar(.visible, for: .navigationBar)
        .task(id: RequestIdentity(route: route, revision: store.revision)) {
            if !model.hasLoaded { await load() }
        }
        .refreshable { await load() }
    }

    private func grid(_ collections: [QQMusicCollection]) -> some View {
        LazyVGrid(columns: DizzyGrid.columns, alignment: .leading, spacing: 22) {
            ForEach(collections) { collection in
                QQMusicCollectionCard(collection: collection, isChart: !isRecommended)
            }
        }
    }

    private func load(append: Bool = false) async { await model.load(store: store, route: sourceRoute, append: append) }

    private struct RequestIdentity: Hashable {
        let route: QQMusicRoute
        let revision: Int
    }
}
