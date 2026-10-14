import Foundation
import Observation

/// Account-scoped server state shared by lists, detail pages and the player.
/// Writes commit only after success; generation/version guards reject stale reads and old accounts.
@Observable final class NeteaseLibrary {
    private let api: NeteaseAPI
    private(set) var userID: Int?
    private(set) var likedIDs = Set<Int>()
    private(set) var orderedLikedIDs: [Int] = []
    private(set) var playlists: [NeteasePlaylist] = []
    private(set) var albums: [NeteaseAlbum] = []
    private(set) var likesLoaded = false
    private(set) var playlistsLoaded = false
    private(set) var albumsLoaded = false
    private(set) var revision = 0
    private(set) var songRevision = 0
    private(set) var playlistRevision = 0
    private(set) var albumRevision = 0
    private var trackRevisions: [Int: Int] = [:]
    func contentRevision(for route: NeteaseRoute?) -> Int {
        switch route {
        case .liked: songRevision
        case .myPlaylists: playlistRevision
        case .subscribedAlbums: albumRevision
        case .playlist(let id): trackRevisions[id, default: 0] + (playlists.contains { $0.id == id && $0.specialType == 5 } ? songRevision : 0)
        default: 0
        }
    }
    private(set) var pending = Set<String>()
    private(set) var albumStates: [Int: Bool] = [:]
    private var playlistStates: [Int: Bool] = [:]
    @ObservationIgnored private var generation = 0
    @ObservationIgnored private var likesTask: Task<[Int], Error>?
    @ObservationIgnored private var playlistsTask: Task<[NeteasePlaylist], Error>?
    @ObservationIgnored private var albumsTask: Task<[NeteaseAlbum], Error>?
    @ObservationIgnored private var albumTasks: [Int: Task<Bool, Error>] = [:]

    init(api: NeteaseAPI) { self.api = api }
    func reset(userID: Int?) {
        generation += 1
        likesTask?.cancel(); playlistsTask?.cancel(); albumsTask?.cancel()
        albumTasks.values.forEach { $0.cancel() }; albumTasks = [:]
        likesTask = nil; playlistsTask = nil; albumsTask = nil
        self.userID = userID
        likedIDs = []; orderedLikedIDs = []; playlists = []; albums = []
        likesLoaded = false; playlistsLoaded = false; albumsLoaded = false
        playlistStates = [:]; albumStates = [:]; pending = []; trackRevisions = [:]
        songRevision = 0; playlistRevision = 0; albumRevision = 0; revision += 1
    }
    func loadLikes(force: Bool = false) async throws {
        guard let userID else { throw NeteaseError.loginRequired }
        if likesLoaded && !force { return }
        let token = generation, version = songRevision
        let task = likesTask ?? Task { try await api.likedSongIDs(userID: userID) }
        likesTask = task
        defer { if token == generation { likesTask = nil } }
        let ids = try await task.value
        try Task.checkCancellation()
        guard token == generation else { throw CancellationError() }
        guard version == songRevision else { return }
        var seen = Set<Int>()
        orderedLikedIDs = ids.filter { seen.insert($0).inserted }; likedIDs = seen; likesLoaded = true
    }
    func loadPlaylists(force: Bool = false) async throws {
        guard let userID else { throw NeteaseError.loginRequired }
        if playlistsLoaded && !force { return }
        let token = generation, version = playlistRevision
        let task = playlistsTask ?? Task { try await api.userPlaylists(userID) }
        playlistsTask = task
        defer { if token == generation { playlistsTask = nil } }
        let values = try await task.value
        try Task.checkCancellation()
        guard token == generation else { throw CancellationError() }
        guard version == playlistRevision else { return }
        var seen = Set<Int>()
        playlists = values.filter { seen.insert($0.id).inserted }
        playlistStates = [:]; playlistsLoaded = true
    }
    func loadAlbums(force: Bool = false) async throws {
        guard userID != nil else { throw NeteaseError.loginRequired }
        if albumsLoaded && !force { return }
        let token = generation, version = albumRevision
        let task = albumsTask ?? Task { try await api.subscribedAlbums() }
        albumsTask = task
        defer { if token == generation { albumsTask = nil } }
        let values = try await task.value
        try Task.checkCancellation()
        guard token == generation else { throw CancellationError() }
        guard version == albumRevision else { return }
        var seen = Set<Int>()
        albums = values.filter { seen.insert($0.id).inserted }; albumsLoaded = true
        albumStates = Dictionary(uniqueKeysWithValues: albums.map { ($0.id, true) })
    }
    func loadAlbumStatus(_ id: Int) async throws {
        guard userID != nil else { throw NeteaseError.loginRequired }
        if albumStates[id] != nil { return }
        if albumsLoaded { albumStates[id] = albums.contains { $0.id == id }; return }
        let token = generation, version = albumRevision
        let task = albumTasks[id] ?? Task { try await api.albumSubscribed(id) }
        albumTasks[id] = task
        defer { if token == generation { albumTasks[id] = nil } }
        let value = try await task.value
        try Task.checkCancellation()
        guard token == generation else { throw CancellationError() }
        if version == albumRevision { albumStates[id] = value }
    }
    func isSubscribed(_ playlist: NeteasePlaylist) -> Bool? {
        if playlist.creator?.userId == userID, userID != nil { return true }
        if let state = playlistStates[playlist.id] { return state }
        if playlistsLoaded { return playlists.contains { $0.id == playlist.id } }
        return playlist.subscribed
    }
    var writablePlaylists: [NeteasePlaylist] {
        playlists.filter { $0.creator?.userId == userID && $0.specialType != 5 }
    }
    func toggleLike(_ id: Int) async throws {
        try await loadLikes()
        guard likesLoaded else { throw NeteaseError.response }
        let liked = !likedIDs.contains(id)
        try await mutate("song/\(id)", request: { try await api.setSongLiked(id, liked: liked) }) {
            songRevision += 1
            if liked { likedIDs.insert(id); orderedLikedIDs.insert(id, at: 0) }
            else { likedIDs.remove(id); orderedLikedIDs.removeAll { $0 == id } }
        }
    }
    func togglePlaylist(_ playlist: NeteasePlaylist) async throws {
        guard playlist.creator?.userId != userID || userID == nil else { return }
        if isSubscribed(playlist) == nil { try await loadPlaylists() }
        guard let previous = isSubscribed(playlist) else { throw NeteaseError.response }
        try await mutate("playlist/\(playlist.id)", request: { try await api.setPlaylistSubscribed(playlist.id, subscribed: !previous) }) {
            playlistRevision += 1
            playlistStates[playlist.id] = !previous
            playlists.removeAll { $0.id == playlist.id }
            if !previous { playlists.insert(playlist, at: 0) }
        }
    }
    func toggleAlbum(_ album: NeteaseAlbum) async throws {
        try await loadAlbumStatus(album.id)
        guard let previous = albumStates[album.id] else { throw NeteaseError.response }
        try await mutate("album/\(album.id)", request: { try await api.setAlbumSubscribed(album.id, subscribed: !previous) }) {
            albumRevision += 1
            albumStates[album.id] = !previous
            albums.removeAll { $0.id == album.id }
            if !previous { albums.insert(album, at: 0) }
        }
    }
    func addSong(_ id: Int, to playlist: NeteasePlaylist) async throws {
        guard playlist.creator?.userId == userID, userID != nil else { throw NeteaseError.loginRequired }
        try await mutate("add/\(playlist.id)/\(id)", request: { try await api.addSong(id, to: playlist.id) }) {
            trackRevisions[playlist.id, default: 0] += 1
        }
    }
    private func mutate(_ key: String, request: () async throws -> Void, commit: () -> Void) async throws {
        guard userID != nil else { throw NeteaseError.loginRequired }
        guard pending.insert(key).inserted else { return }
        let token = generation
        defer { if token == generation { pending.remove(key) } }
        try await request()
        try Task.checkCancellation()
        guard token == generation else { throw CancellationError() }
        commit(); revision += 1
    }
}
