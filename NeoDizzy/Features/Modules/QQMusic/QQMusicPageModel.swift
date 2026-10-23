import Foundation
import Observation

/// Page-owned results. Request identity includes the account revision so a stale response
/// cannot replace the content after account changes or module deactivation.
@MainActor @Observable
final class QQMusicPageModel {
    private(set) var songs: [QQMusicSong] = []
    private(set) var albums: [QQMusicAlbum] = []
    private(set) var artists: [QQMusicArtist] = []
    private(set) var biography = ""
    private(set) var libraryRevision = -1
    private(set) var playlists: [QQMusicCollection] = []
    private(set) var charts: [QQMusicCollection] = []
    private(set) var chartGroups: [QQMusicChartGroup] = []
    private(set) var title = ""
    private(set) var artwork: URL?
    private(set) var loading = false
    private(set) var hasLoaded = false
    private(set) var more = false
    private(set) var error: String?
    private(set) var retryAppend = false
    private(set) var dailyDate: Date?
    private let now: () -> Date
    private var nextPage = 1
    private var nextOffset = 0
    private var nextCursor: Int?
    private var consumedCursors = Set<Int>()
    private var generation = 0
    private var loadedRoute: QQMusicRoute?
    private var loadedRevision: Int?
    @ObservationIgnored private var loadTask: Task<Void, Never>?
    @ObservationIgnored private var loadingAppend = false

    init(now: @escaping () -> Date = { .now }) { self.now = now }

    var needsDailyRefresh: Bool {
        dailyDate != Calendar.current.startOfDay(for: now())
    }

    func reset() {
        loadTask?.cancel(); loadTask = nil
        generation += 1
        songs = []; playlists = []; charts = []; chartGroups = []; albums = []; artists = []; biography = ""; libraryRevision = -1
        title = ""; artwork = nil; loading = false; hasLoaded = false
        more = false; error = nil; retryAppend = false
        nextPage = 1; nextOffset = 0; nextCursor = nil; consumedCursors.removeAll()
        loadedRoute = nil; loadedRevision = nil; loadingAppend = false
        dailyDate = nil
    }

    func load(store: QQMusicStore, route: QQMusicRoute? = nil, append: Bool = false) async {
        guard store.active, !Task.isCancelled else { return }
        if append && (loading || !more || loadedRevision != store.revision || loadedRoute != route) { return }
        let revision = store.revision
        let contentRevision = Self.contentRevision(store: store, route: route)
        if !append, !loadingAppend, loadedRevision == revision, loadedRoute == route, libraryRevision == contentRevision, let loadTask {
            // Home and "view all" can share this page. Each caller waits for the
            // same model-owned request; removing one view must not cancel it.
            await loadTask.value
            return
        }
        if loadedRevision != revision || loadedRoute != route || libraryRevision != contentRevision {
            reset()
        } else {
            // An explicit refresh replaces a pending append while preserving
            // already published content until the refresh succeeds.
            loadTask?.cancel(); loadTask = nil
        }
        loadedRevision = revision; loadedRoute = route; libraryRevision = contentRevision
        generation += 1
        let token = generation
        loading = true; error = nil; retryAppend = append; loadingAppend = append
        let task = Task { await performLoad(store: store, route: route, append: append, revision: revision, token: token) }
        loadTask = task
        await task.value
    }

    private func performLoad(store: QQMusicStore, route: QQMusicRoute?, append: Bool, revision: Int, token: Int) async {
        let requestDate = Calendar.current.startOfDay(for: now())
        defer {
            if token == generation { loading = false; loadTask = nil; loadingAppend = false }
        }
        do {
            try Task.checkCancellation()
            var newAlbums: [QQMusicAlbum] = []
            var newArtists: [QQMusicArtist] = []
            var newBiography = ""
            var browsePage: QQMusicBrowsePage?
            let offset = append ? nextOffset : 0
            var newSongs: [QQMusicSong] = []
            var newPlaylists: [QQMusicCollection] = []
            var newCharts: [QQMusicCollection] = []
            var newChartGroups: [QQMusicChartGroup] = []
            var newTitle = route?.title ?? "排行榜"
            var newArtwork: URL?
            var hasMore = false
            let page = append ? nextPage : 1
            let cursor = append ? nextCursor ?? 0 : 0
            var followingCursor: Int?
            switch route {
            case .search(let query):
                let query = query.trimmingCharacters(in: .whitespacesAndNewlines)
                if !query.isEmpty { newSongs = try await store.api.search(query: query, page: page) }
                newTitle = query
                // General search may return fewer than requested (e.g. ten songs).
                // Only an empty or repeated page proves there are no further results.
                hasMore = !newSongs.isEmpty
            case .typedSearch(let query, let kind):
                let query = query.trimmingCharacters(in: .whitespacesAndNewlines)
                if !query.isEmpty { browsePage = try await store.api.search(query: query, kind: kind, page: page) }
                newTitle = query
            case .artist(let mid):
                browsePage = try await store.api.artistSongs(mid: mid, offset: offset)
                if append {
                    newTitle = title; newArtwork = artwork; newBiography = biography
                } else {
                    let artist = try await store.api.artist(mid: mid)
                    newTitle = artist.name; newArtwork = artist.coverURL; newBiography = artist.biography
                }
            case .artistAlbums(let mid): browsePage = try await store.api.artistAlbums(mid: mid, offset: offset)
            case .artists: browsePage = try await store.api.artists(offset: offset, page: page)
            case .newAlbums(let area): browsePage = try await store.api.newAlbums(area: area, offset: offset)
            case .similar(let mid): newSongs = try await store.api.similarSongs(mid: mid)
            case .song(let mid):
                let song = try await store.api.song(mid: mid)
                newSongs = [song]; newTitle = song.title; newArtwork = song.coverURL
            case .album(let mid):
                let collection = try await store.api.album(mid: mid)
                newSongs = collection.songs.enumerated().sorted {
                    ($0.element.discNumber ?? 1, $0.element.trackNumber ?? Int.max, $0.offset)
                    < ($1.element.discNumber ?? 1, $1.element.trackNumber ?? Int.max, $1.offset)
                }.map(\.element)
                newTitle = collection.title; newArtwork = collection.coverURL
            case .playlist(let id):
                let collection = try await store.api.playlist(id: id)
                newSongs = collection.songs; newTitle = collection.title; newArtwork = collection.coverURL
            case .chart(let id):
                let collection = try await store.api.chart(id: id)
                newSongs = collection.songs; newTitle = collection.title; newArtwork = collection.coverURL
            case .recommended:
                let result = try await store.api.recommendedPlaylists(cursor: cursor, limit: 30)
                newPlaylists = result.items; followingCursor = result.nextCursor
            case .radar:
                let result = try await store.api.radarSongs(page: page)
                newSongs = result.items; hasMore = result.hasMore && !result.items.isEmpty
            case .daily:
                newSongs = try await store.api.dailySongs()
            case .chartGroup(let id):
                let groups = try await store.api.chartGroups()
                newChartGroups = groups.filter { $0.id == id }
                newCharts = newChartGroups.flatMap(\.charts)
                newTitle = newChartGroups.first?.title ?? newTitle
            case nil, .charts:
                newChartGroups = try await store.api.chartGroups()
                newCharts = newChartGroups.flatMap(\.charts)
            }
            if let browsePage {
                newSongs = browsePage.songs; newAlbums = browsePage.albums
                newArtists = browsePage.artists; newPlaylists = browsePage.playlists
                hasMore = browsePage.nextPage != nil || browsePage.nextOffset != nil
            }
            try Task.checkCancellation()
            guard libraryRevision == Self.contentRevision(store: store, route: route) else { return }
            guard token == generation, store.active, store.revision == revision else { return }
            var seen = Set<String>()
            let combined = (append ? songs : []) + newSongs
            let uniqueSongs = combined.filter { seen.insert($0.mid).inserted }
            var playlistIDs = Set<String>()
            let combinedPlaylists = (append ? playlists : []) + newPlaylists
            let uniquePlaylists = combinedPlaylists.filter { playlistIDs.insert($0.id).inserted }
            let uniqueAlbums = unique((append ? albums : []) + newAlbums)
            let uniqueArtists = unique((append ? artists : []) + newArtists)
            // Stop when a server repeats a page, even if it advertises a full page.
            if route == .recommended {
                var cursors = append ? consumedCursors : []
                cursors.insert(cursor)
                let hasNewItems = append ? uniquePlaylists.count > playlists.count : !uniquePlaylists.isEmpty
                more = hasNewItems && followingCursor.map { !cursors.contains($0) } == true
                nextCursor = more ? followingCursor : nil
                consumedCursors = cursors
            } else {
                more = hasMore && (!append || uniqueSongs.count > songs.count || uniquePlaylists.count > playlists.count || uniqueAlbums.count > albums.count || uniqueArtists.count > artists.count)
                nextCursor = nil; consumedCursors.removeAll()
            }
            albums = uniqueAlbums; artists = uniqueArtists; biography = newBiography
            songs = uniqueSongs
            playlists = uniquePlaylists
            var chartIDs = Set<String>()
            charts = newCharts.filter { chartIDs.insert($0.id).inserted }
            chartGroups = newChartGroups
            title = newTitle; artwork = newArtwork ?? songs.first?.coverURL
            nextPage = browsePage?.nextPage ?? page + 1
            nextOffset = browsePage?.nextOffset ?? 0; hasLoaded = true
            dailyDate = route == .daily ? requestDate : nil
        } catch is CancellationError {
        } catch {
            guard token == generation, store.active, store.revision == revision, !Task.isCancelled else { return }
            self.error = error.localizedDescription
        }
    }

    private func unique<T: Identifiable>(_ values: [T]) -> [T] {
        var seen = Set<T.ID>()
        return values.filter { seen.insert($0.id).inserted }
    }

    static func contentRevision(store: QQMusicStore, route: QQMusicRoute?) -> Int {
        if case .playlist(let id) = route { store.library.contentRevision(playlistID: id) } else { -1 }
    }
}
