import SwiftUI

struct NeteaseHomeSections: View {
    let personal: NeteasePageModel
    let refreshRevision: Int
    @Environment(NeteaseStore.self) private var store
    private var visibleBlocks: [NeteaseHomeBlock] {
        var seen = Set<String>()
        return personal.blocks.filter { block in
            let hiddenTitles = ["猜你喜欢", "热门歌手", "新歌推荐", "黑胶vip专享"]
            let normalizedTitle = block.title.components(separatedBy: .whitespacesAndNewlines).joined().lowercased()
            // Style recommendations use changing editorial titles, so exclude the section by its stable code.
            return block.blockCode != "HOMEPAGE_BLOCK_STYLE_RCMD"
                && !hiddenTitles.contains(where: { normalizedTitle.contains($0) })
                && (!block.playlists.isEmpty || !block.songs.isEmpty)
                && seen.insert(block.id).inserted
        }
    }
    var body: some View {
        if store.profile != nil {
            ForEach(visibleBlocks.prefix(5)) { block in
                VStack(alignment: .leading, spacing: 14) {
                    Text(block.title).font(.title2.bold()).accessibilityAddTraits(.isHeader)
                    if !block.playlists.isEmpty { NeteaseCoverShelf(playlists: Array(block.playlists.prefix(8))) }
                    if !block.songs.isEmpty { NeteaseSongRows(songs: Array(block.songs.prefix(3))) }
                }
            }
            if personal.showsInitialSkeleton {
                VStack(alignment: .leading, spacing: 14) {
                    Text("个性化推荐").font(.title2.bold()).redacted(reason: .placeholder)
                    NeteaseSkeleton(layout: .shelf)
                }
                .accessibilityElement(children: .ignore)
                .accessibilityLabel("正在加载个性化推荐")
            }
            if let error = personal.error {
                VStack(alignment: .leading, spacing: 8) {
                    Text("个性化推荐暂不可用：\(error)").font(.footnote).foregroundStyle(.secondary)
                    Button("重试") { Task { await personal.load(api: store.api, userID: store.profile?.userId, kind: 0, refresh: true) } }
                }
            }
        }
        ForEach([NeteaseRoute.recommended, .charts, .newAlbums(.all), .quality], id: \.self) { route in
            NeteaseHomeSection(route: route, refreshRevision: refreshRevision)
        }
    }
}

private struct NeteaseHomeSection: View {
    let route: NeteaseRoute
    let refreshRevision: Int
    @Environment(NeteaseStore.self) private var store
    @Environment(NeteaseContentCache.self) private var cache
    private var model: NeteasePageModel { cache.page(.route(route), revision: store.revision) }
    @State private var observedRefresh = -1
    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            NavigationLink(value: AppRoute.netease(route)) {
                HStack {
                    Text(route.title).font(.title2.bold())
                    Spacer()
                    Image(systemName: "chevron.right").font(.subheadline.weight(.semibold)).foregroundStyle(.secondary)
                }.foregroundStyle(.primary)
            }.buttonStyle(.plain).accessibilityLabel("查看全部\(route.title)")
            if !model.playlists.isEmpty || !model.albums.isEmpty || !model.artists.isEmpty {
                NeteaseCoverShelf(playlists: Array(model.playlists.prefix(8)), albums: Array(model.albums.prefix(8)), artists: Array(model.artists.prefix(8)))
            }
            if !model.songs.isEmpty { NeteaseSongRows(songs: Array(model.songs.prefix(3))) }
            if model.showsInitialSkeleton { NeteaseSkeleton(layout: .shelf) }
            if let error = model.error {
                HStack {
                    Text(error).font(.footnote).foregroundStyle(.secondary)
                    Spacer()
                    Button("重试") { Task { await load() } }
                }
            } else if model.hasLoaded && model.isEmpty && !model.loading {
                Text("暂无内容").font(.subheadline).foregroundStyle(.secondary)
            }
        }
        .task(id: "\(store.revision)/\(refreshRevision)") {
            let shouldRefresh = observedRefresh >= 0 && observedRefresh != refreshRevision
            observedRefresh = refreshRevision
            if !model.hasLoaded || shouldRefresh { await load() }
        }
    }
    private func load() async { await model.load(api: store.api, route: route, userID: store.profile?.userId) }
}

struct NeteaseCoverShelf: View {
    var playlists: [NeteasePlaylist] = []
    var albums: [NeteaseAlbum] = []
    var artists: [NeteaseArtist] = []
    @Environment(\.dynamicTypeSize) private var typeSize
    var body: some View {
        ScrollView(.horizontal) {
            LazyHStack(alignment: .top, spacing: 14) {
                ForEach(playlists) { item in card(item.name, artwork: item.artworkURL, route: .playlist(item.id)) }
                ForEach(albums) { item in card(item.name, artwork: item.artworkURL, route: .album(item.id)) }
                ForEach(artists) { item in card(item.name, artwork: item.artworkURL, route: .artist(item.id)) }
            }
        }
        .scrollIndicators(.hidden)
        .contentMargins(.horizontal, 20, for: .scrollContent)
        // Extend the viewport through MainTabPage's inset while keeping resting cards aligned with its headings.
        .padding(.horizontal, -20)
    }
    private func card(_ title: String, artwork: URL?, route: NeteaseRoute) -> some View {
        NavigationLink(value: AppRoute.netease(route)) {
            DiscCard(disc: DiscSummary(id: String(describing: route), title: title, coverURL: artwork), showsLabel: false,
                     reservesTitleLines: true)
                .frame(width: typeSize.isAccessibilitySize ? 220 : 156)
                .fixedSize(horizontal: false, vertical: true)
        }.buttonStyle(.plain)
    }
}

struct NeteaseLibraryLinks: View {
    var body: some View {
        VStack(spacing: 0) {
            entry(.liked, image: "heart.fill")
            Divider()
            entry(.subscribedAlbums, image: "square.stack")
            Divider()
            entry(.recent, image: "clock")
        }
    }
    private func entry(_ route: NeteaseRoute, image: String) -> some View {
        NavigationLink(value: AppRoute.netease(route)) {
            HStack {
                Label(route.title, systemImage: image)
                Spacer()
                Image(systemName: "chevron.right").font(.footnote).foregroundStyle(.secondary)
            }.padding(.vertical, 14).contentShape(.rect)
        }.buttonStyle(.plain)
    }
}

/// Static placeholders mirror the content geometry without timers, fake models, or tappable controls.
enum NeteaseSkeletonLayout {
    case shelf, grid, songs
}

struct NeteaseSkeleton: View {
    let layout: NeteaseSkeletonLayout
    @Environment(\.dynamicTypeSize) private var typeSize

    var body: some View {
        Group {
            switch layout {
            case .shelf:
                ScrollView(.horizontal) {
                    HStack(alignment: .top, spacing: 14) {
                        ForEach(0..<4) { _ in
                            card.frame(width: typeSize.isAccessibilitySize ? 220 : 156)
                        }
                    }
                }
                .scrollIndicators(.hidden)
                .contentMargins(.horizontal, 20, for: .scrollContent)
                .padding(.horizontal, -20)
            case .grid:
                LazyVGrid(columns: DizzyGrid.columns, alignment: .leading, spacing: 22) {
                    ForEach(0..<6) { _ in card }
                }
            case .songs:
                VStack(spacing: 0) {
                    ForEach(0..<6) { _ in
                        HStack(spacing: 12) {
                            RoundedRectangle(cornerRadius: 3).fill(.gray.opacity(0.18))
                                .frame(width: 18, height: 18)
                            Text("歌曲名称正在载入").font(.body).redacted(reason: .placeholder)
                            Spacer(minLength: 12)
                            Capsule().fill(.gray.opacity(0.18)).frame(width: 22, height: 6)
                                .frame(width: 42, height: 44)
                        }
                        .padding(.leading, 20).padding(.trailing, 8).padding(.vertical, 11)
                    }
                }
            }
        }
        .allowsHitTesting(false)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("正在加载内容")
    }

    private var card: some View {
        VStack(alignment: .leading, spacing: 6) {
            RoundedRectangle(cornerRadius: 10)
                .fill(.gray.opacity(0.18))
                .aspectRatio(1, contentMode: .fit)
            Text("音乐与故事\n等待与你相遇")
                .font(.subheadline.weight(.semibold)).lineLimit(2)
                .redacted(reason: .placeholder)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}
