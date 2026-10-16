import SwiftUI

/// 统一搜索：按来源分组显示资料库和各平台的结果。
/// 打字停顿一会儿或按搜索键才搜索；没有输入时显示最近搜索和「接着听」。
struct UnifiedSearchView: View {
    @Environment(ModuleRegistry.self) private var modules
    @Environment(ModuleSettings.self) private var tabs
    @Environment(SearchPresentation.self) private var search
    @State private var submitted = ""
    @State private var recent = RecentSearches()
    private var trimmed: String { search.text.trimmingCharacters(in: .whitespacesAndNewlines) }

    var body: some View {
        @Bindable var search = search
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 24) {
                if submitted.isEmpty {
                    recentSearches
                    ContinueListening()
                } else {
                    SearchResultsList(query: submitted, modules: tabs.visibleModules).id(submitted)
                }
            }
            .padding(.horizontal, 20)
            .padding(.top, 8)
            .padding(.bottom, 24)
        }
        .scrollDismissesKeyboard(.interactively)
        .dizzyPageBackground()
        .navigationTitle("搜索")
        .navigationBarTitleDisplayMode(.large)
        // 与 MeloX 相同：搜索框固定在页面顶部，不挂在标签栏上；手势收起键盘只收起键盘，关键词和结果保留。
        .searchable(text: $search.text, isPresented: $search.isActive,
                    placement: .navigationBarDrawer(displayMode: .always), prompt: Text("歌曲、专辑、歌单、社团"))
        .onSubmit(of: .search) { submit(trimmed) }
        // 停止输入一会儿后自动搜索；清空输入回到最近搜索。
        .task(id: trimmed) {
            guard !trimmed.isEmpty else { submitted = ""; return }
            guard trimmed != submitted else { return }
            do { try await Task.sleep(for: .milliseconds(600)) } catch { return }
            submitted = trimmed
        }
    }

    @ViewBuilder
    private var recentSearches: some View {
        if !recent.items.isEmpty {
            VStack(alignment: .leading, spacing: 10) {
                HStack(alignment: .firstTextBaseline) {
                    Text("最近搜索").font(.title3.bold()).accessibilityAddTraits(.isHeader)
                    Spacer()
                    Button("清除") { recent.clear() }.font(.subheadline)
                }
                FlowLayout(spacing: 8) {
                    ForEach(recent.items, id: \.self) { item in
                        Button(item) {
                            search.text = item
                            submit(item)
                        }
                        .font(.subheadline)
                        .foregroundStyle(DizzyPalette.text)
                        .padding(.horizontal, 14)
                        .frame(minHeight: 36)
                        .background(DizzyPalette.surface, in: .capsule)
                        .buttonStyle(.plain)
                        .contextMenu { Button("删除", systemImage: "trash", role: .destructive) { recent.remove(item) } }
                    }
                }
            }
        }
    }

    private func submit(_ query: String) {
        guard !query.isEmpty else { return }
        submitted = query
        recent.add(query)
    }
}

/// 一次搜索的结果：各来源的分组，资料库在最前。
private struct SearchResultsList: View {
    let query: String
    let modules: [ModuleID]
    @Environment(ModuleRegistry.self) private var registry

    var body: some View {
        ForEach(registry.searchSections(query: query, in: modules), id: \.id) { $0.view }
    }
}

/// 没有输入时的「接着听」：最近播放过的专辑，点一下打开。
private struct ContinueListening: View {
    @Environment(PlaybackHistoryStore.self) private var history
    @Environment(OfflineLibraryStore.self) private var library

    var body: some View {
        let entries = Array(history.entries.lazy.filter(isAvailable).prefix(6))
        if entries.isEmpty {
            ContentUnavailableView("搜索资料库、网易云和 DizzyLab", systemImage: "magnifyingglass",
                                   description: Text("一次搜索，按来源列出结果。"))
                .padding(.top, 40)
        } else {
            SearchGroup(title: String(localized: "接着听")) {
                ForEach(Array(entries.enumerated()), id: \.element.id) { index, entry in
                    SearchCardRow(isLast: index == entries.count - 1, separatorInset: 66) {
                        NavigationLink(value: route(entry)) {
                            SearchMediaRow(title: entry.title, subtitle: "\(source(entry)) · \(entry.subtitle)", artworkURL: entry.coverURL)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
    }

    /// 本地专辑被删掉后不再显示。
    private func isAvailable(_ entry: PlaybackHistoryStore.Entry) -> Bool {
        entry.kind != .localAlbum || library.localAlbum(id: entry.itemID) != nil
    }

    private func route(_ entry: PlaybackHistoryStore.Entry) -> AppRoute {
        switch entry.kind {
        case .localAlbum: .localAlbum(id: library.localAlbum(id: entry.itemID)?.id ?? entry.itemID)
        case .neteaseAlbum: .netease(.album(Int(entry.itemID) ?? 0))
        case .dizzylabAlbum: .disc(id: entry.itemID)
        }
    }

    private func source(_ entry: PlaybackHistoryStore.Entry) -> String {
        switch entry.kind {
        case .localAlbum: String(localized: "本地")
        case .neteaseAlbum: String(localized: "网易云")
        case .dizzylabAlbum: "DizzyLab"
        }
    }
}

/// 搜索页搜索框的状态：选中「搜索」标签时自动进入输入。
@Observable
final class SearchPresentation {
    var text = ""
    var isActive = false
}

/// 最近搜索的关键词，最新的在前，最多 10 个，保存在本机。
@MainActor
@Observable
private final class RecentSearches {
    private(set) var items: [String]
    private static let key = "search.recent.v1"
    private static let limit = 10

    init() { items = UserDefaults.standard.stringArray(forKey: Self.key) ?? [] }

    func add(_ query: String) {
        items.removeAll { $0 == query }
        items.insert(query, at: 0)
        items = Array(items.prefix(Self.limit))
        save()
    }

    func remove(_ query: String) {
        items.removeAll { $0 == query }
        save()
    }

    func clear() {
        items = []
        save()
    }

    private func save() { UserDefaults.standard.set(items, forKey: Self.key) }
}
