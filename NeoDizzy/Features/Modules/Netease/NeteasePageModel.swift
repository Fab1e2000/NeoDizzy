import SwiftUI

@Observable
final class NeteasePageModel {
    var playlists: [NeteasePlaylist] = []
    var albums: [NeteaseAlbum] = []
    var artists: [NeteaseArtist] = []
    var blocks: [NeteaseHomeBlock] = []
    var playlist: NeteasePlaylist?
    var album: NeteaseAlbum?
    var detailDescription = ""
    var cursor = 0
    var libraryRevision = -1
    var songs: [NeteaseSong] = []
    var title = ""
    var artwork: URL?
    var error: String?
    var loading = false
    var remaining: [Int] = []
    var offset = 0
    var more = false
    var didUpdate: ((NeteasePageModel) -> Void)?
    private(set) var hasLoaded = false
    private var loadTask: Task<Void, Never>?
    private var generation = 0

    func reset() {
        loadTask?.cancel(); loadTask = nil; hasLoaded = false
        generation += 1
        playlists = []; albums = []; songs = []; artists = []; blocks = []; remaining = []
        playlist = nil; album = nil; detailDescription = ""; cursor = 0; libraryRevision = -1
        title = ""; artwork = nil; error = nil; offset = 0; more = false; loading = false
    }
    func load(api: NeteaseAPI, route: NeteaseRoute? = nil, userID: Int? = nil,
              query: String = "", kind: Int = 1000, append: Bool = false, library: NeteaseLibrary? = nil, refresh: Bool = false) async {
        let startingRevision = library?.contentRevision(for: route) ?? -1
        if let loadTask { await loadTask.value }
        else {
            let task = Task { await performLoad(api: api, route: route, userID: userID, query: query, kind: kind, append: append, library: library, refresh: refresh) }
            loadTask = task
            await task.value
        }
        // A mutation during a read invalidates that read, then the same callers share its replacement.
        if let library, startingRevision != library.contentRevision(for: route), error == nil {
            await load(api: api, route: route, userID: userID, query: query, kind: kind, library: library)
        }
    }
    private func performLoad(api: NeteaseAPI, route: NeteaseRoute?, userID: Int?, query: String, kind: Int, append: Bool, library: NeteaseLibrary?, refresh: Bool) async {
        guard !Task.isCancelled else { return }
        loading = true; error = nil
        let token = generation
        let contentRevision = library?.contentRevision(for: route) ?? -1
        defer { if generation == token { loading = false; loadTask = nil } }
        do {
            var newPlaylists: [NeteasePlaylist] = [], newAlbums: [NeteaseAlbum] = [], newSongs: [NeteaseSong] = []
            var newArtists: [NeteaseArtist] = [], newBlocks: [NeteaseHomeBlock] = []
            var newPlaylist = playlist, newAlbum = album, newDescription = detailDescription, newCursor = cursor
            var newTitle = title, newArtwork = artwork, newRemaining: [Int] = [], hasMore = false
            let start = append ? offset : 0
            if !query.isEmpty {
                let result = try await api.search(query, kind: kind, offset: start)
                newArtists = result.artists ?? []
                newSongs = result.songs ?? []; newAlbums = result.albums ?? []; newPlaylists = result.playlists ?? []
                let count = kind == 1 ? result.songCount : kind == 10 ? result.albumCount : kind == 100 ? result.artistCount : result.playlistCount
                hasMore = start + 30 < (count ?? 0)
            } else if let route {
                switch route {
                case .album(let id):
                    let result = try await api.album(id)
                    newAlbum = result.0
                    newDescription = result.0.description ?? ""
                    newAlbums = []; newSongs = result.1; newTitle = result.0.name; newArtwork = result.0.artworkURL
                case .playlist(let id):
                    let ids: [Int]
                    if append { ids = remaining }
                    else {
                        let playlist = try await api.playlist(id)
                        newPlaylist = playlist; newDescription = playlist.description ?? ""
                        newTitle = playlist.name; newArtwork = playlist.artworkURL
                        guard token == generation, !Task.isCancelled else { return }
                        title = newTitle; artwork = newArtwork
                        didUpdate?(self)
                        ids = playlist.trackIds?.map(\.id) ?? playlist.tracks?.map(\.id) ?? []
                        let firstIDs = Array(ids.prefix(100))
                        let embedded = Dictionary((playlist.tracks ?? []).map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
                        if firstIDs.allSatisfy({ embedded[$0] != nil }) { newSongs = firstIDs.compactMap { embedded[$0] } }
                    }
                    if newSongs.isEmpty && !ids.isEmpty { newSongs = try await api.songs(Array(ids.prefix(100))) }
                    newRemaining = Array(ids.dropFirst(100)); hasMore = !newRemaining.isEmpty
                case .charts: newPlaylists = try await api.charts()
                case .daily: newSongs = try await api.daily()
                case .radio: newSongs = try await api.radio()
                case .myPlaylists:
                    guard let userID else { throw NeteaseError.loginRequired }
                    if let library { try await library.loadPlaylists(force: refresh); newPlaylists = library.playlists }
                    else { newPlaylists = try await api.userPlaylists(userID) }
                case .liked:
                    guard let userID else { throw NeteaseError.loginRequired }
                    let ids: [Int]
                    if append { ids = remaining }
                    else if let library { try await library.loadLikes(force: refresh); ids = library.orderedLikedIDs }
                    else { ids = try await api.likedSongIDs(userID: userID) }
                    newSongs = try await api.songs(Array(ids.prefix(100)))
                    newRemaining = Array(ids.dropFirst(100)); hasMore = !newRemaining.isEmpty
                case .recent: newSongs = try await api.recentSongs()
                case .subscribedAlbums:
                    if let library { try await library.loadAlbums(force: refresh); newAlbums = library.albums }
                    else { newAlbums = try await api.subscribedAlbums() }
                case .recommended: newPlaylists = try await api.recommended()
                case .quality:
                    let page = try await api.qualityPlaylists(before: append ? cursor : 0)
                    newPlaylists = page.items; newCursor = page.cursor
                    hasMore = page.more && page.cursor > 0 && (!append || page.cursor != cursor) && !page.items.isEmpty
                case .category(let category):
                    let page = try await api.categorizedPlaylists(category, offset: start)
                    newPlaylists = page.items; hasMore = page.more && !page.items.isEmpty
                case .newAlbums(let region): newAlbums = try await api.albums(offset: start, region: region); hasMore = newAlbums.count == 30
                case .newSongs(let region): newSongs = try await api.newSongs(region: region)
                case .personalizedSongs: newSongs = try await api.personalizedSongs()
                case .artists: newArtists = try await api.topArtists()
                case .artist(let id):
                    let result = try await api.artist(id)
                    newTitle = result.artist.name; newArtwork = result.artist.artworkURL
                    newDescription = result.artist.briefDesc ?? ""; newSongs = result.songs
                case .artistAlbums(let id):
                    let page = try await api.artistAlbums(id, offset: start)
                    newAlbums = page.items; hasMore = page.more
                case .similar(let id): newSongs = try await api.similarSongs(id)
                // 搜索页按关键词加载（上面的 query 分支），不走路由。
                case .search: break
                }
            } else if kind == 0 {
                if userID != nil { newBlocks = try await api.homeFeed(refresh: refresh).blocks }
            } else if kind == 10 {
                newAlbums = try await api.albums(offset: start); hasMore = newAlbums.count == 30
            } else { newPlaylists = try await api.recommended() }
            try Task.checkCancellation()
            guard token == generation, contentRevision == (library?.contentRevision(for: route) ?? -1) else { return }
            if append {
                playlists = unique(playlists + newPlaylists); albums = unique(albums + newAlbums)
                songs = unique(songs + newSongs); artists = unique(artists + newArtists)
            }
            else { playlists = unique(newPlaylists); albums = unique(newAlbums); songs = unique(newSongs); artists = unique(newArtists) }
            blocks = newBlocks; playlist = newPlaylist; album = newAlbum; detailDescription = newDescription; cursor = newCursor
            libraryRevision = contentRevision
            title = newTitle; artwork = newArtwork ?? newSongs.first?.album?.artworkURL
            remaining = newRemaining; more = hasMore; offset = start + 30
            hasLoaded = true
            didUpdate?(self)
        } catch is CancellationError { }
        catch { if token == generation && !Task.isCancelled { self.error = error.localizedDescription } }
    }
    private func unique<T: Identifiable>(_ values: [T]) -> [T] {
        var seen = Set<T.ID>()
        return values.filter { seen.insert($0.id).inserted }
    }
    /// Includes the first frame before the loading task starts, but never hides errors or loaded content.
    var showsInitialSkeleton: Bool { isEmpty && error == nil && (!hasLoaded || loading) }

    var isEmpty: Bool { playlists.isEmpty && albums.isEmpty && songs.isEmpty && artists.isEmpty && blocks.isEmpty }
}

