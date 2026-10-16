import SwiftUI

/// Module-lifetime page data. Private pages and pending work are discarded on account changes.
@Observable
final class NeteaseContentCache {
    enum Key: Hashable { case home(String, Int), route(NeteaseRoute) }
    private let prepareArtwork: ([URL]) async -> Void
    init(prepareArtwork: @escaping ([URL]) async -> Void = { await AlbumArtworkPreload.prepareFirstScreen($0) }) {
        self.prepareArtwork = prepareArtwork
    }
    @ObservationIgnored private var pages: [Key: NeteasePageModel] = [:]
    @ObservationIgnored private var revision = -1
    @ObservationIgnored private var shortcutTask: Task<Void, Never>?
    @ObservationIgnored private var artworkTask: Task<Void, Never>?
    @ObservationIgnored private var pendingArtwork: [URL] = []
    @ObservationIgnored private var scheduledArtwork = Set<URL>()

    func page(_ key: Key, revision: Int) -> NeteasePageModel {
        if self.revision != revision {
            shortcutTask?.cancel(); shortcutTask = nil
            artworkTask?.cancel(); artworkTask = nil
            pendingArtwork.removeAll(); scheduledArtwork.removeAll()
            pages.values.forEach { $0.reset() }; pages.removeAll()
            self.revision = revision
        }
        if let page = pages[key] { return page }
        let page = NeteasePageModel()
        page.didUpdate = { [weak self] page in
            guard let self, self.revision == revision else { return }
            for playlist in page.playlists + page.blocks.flatMap(\.playlists) {
                self.seed(.playlist(playlist.id), title: playlist.name, artwork: playlist.artworkURL, revision: revision)
            }
            for album in page.albums {
                self.seed(.album(album.id), title: album.name, artwork: album.artworkURL, revision: revision)
            }
            for artist in page.artists {
                self.seed(.artist(artist.id), title: artist.name, artwork: artist.artworkURL, revision: revision)
            }
            let urls = page.playlists.compactMap(\.artworkURL) + page.albums.compactMap(\.artworkURL)
                + page.artists.compactMap(\.artworkURL) + page.blocks.flatMap(\.playlists).compactMap(\.artworkURL)
                + [page.artwork].compactMap { $0 } + page.songs.prefix(3).compactMap { $0.album?.artworkURL }
                + page.blocks.flatMap(\.songs).prefix(3).compactMap { $0.album?.artworkURL }
            self.enqueueArtwork(Array(urls.prefix(12)), revision: revision)
        }
        pages[key] = page
        return page
    }

    private func enqueueArtwork(_ urls: [URL], revision: Int) {
        pendingArtwork += urls.filter { scheduledArtwork.insert($0).inserted }
        guard artworkTask == nil, !pendingArtwork.isEmpty else { return }
        artworkTask = Task {
            defer { if self.revision == revision { artworkTask = nil } }
            while !pendingArtwork.isEmpty && self.revision == revision && !Task.isCancelled {
                let batch = Array(pendingArtwork.prefix(3))
                pendingArtwork.removeFirst(batch.count)
                await prepareArtwork(batch)
            }
        }
    }

    private func seed(_ route: NeteaseRoute, title: String, artwork: URL?, revision: Int) {
        let page = page(.route(route), revision: revision)
        if page.title.isEmpty { page.title = title }
        if page.artwork == nil { page.artwork = artwork }
    }

    func prewarmShortcuts(store: NeteaseStore) {
        _ = page(.home("", 1000), revision: store.revision)
        guard shortcutTask == nil else { return }
        let revision = store.revision
        let userID = store.profile?.userId
        let routes: [NeteaseRoute] = userID == nil ? [.charts] : [.charts, .daily, .radio]
        // Sequential API requests and bounded artwork work, only once per module session.
        shortcutTask = Task {
            for route in routes {
                guard !Task.isCancelled, self.revision == revision else { return }
                let model = page(.route(route), revision: revision)
                if !model.hasLoaded { await model.load(api: store.api, route: route, userID: userID, library: store.library) }
            }
        }
    }
}
