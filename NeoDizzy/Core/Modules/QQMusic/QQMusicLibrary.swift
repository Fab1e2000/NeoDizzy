import Foundation
import Observation

/// Account-owned state. Complete reads and successful writes alone can publish;
/// generation and content revisions reject old accounts and reads overtaken by a write.
@Observable @MainActor final class QQMusicLibrary {
    private let api: QQMusicClient
    private(set) var accountID: String?
    private(set) var likedSongs: [QQMusicSong] = []
    private(set) var playlists: [QQMusicLibraryPlaylist] = []
    private(set) var albums: [QQMusicLibraryAlbum] = []
    private(set) var likesLoaded = false
    private(set) var playlistsLoaded = false
    private(set) var albumsLoaded = false
    private(set) var revision = 0
    private(set) var songRevision = 0
    private(set) var playlistRevision = 0
    private(set) var albumRevision = 0
    private(set) var pending = Set<String>()
    private var trackRevisions: [String: Int] = [:]
    @ObservationIgnored private var generation = UUID()
    @ObservationIgnored private var likesTask: QQMusicLibraryRead<[QQMusicSong]>?
    @ObservationIgnored private var playlistsTask: QQMusicLibraryRead<[QQMusicLibraryPlaylist]>?
    @ObservationIgnored private var albumsTask: QQMusicLibraryRead<[QQMusicLibraryAlbum]>?

    init(api: QQMusicClient) { self.api = api }

    func reset(accountID: String?) {
        generation = UUID()
        likesTask?.task.cancel(); playlistsTask?.task.cancel(); albumsTask?.task.cancel()
        likesTask = nil; playlistsTask = nil; albumsTask = nil
        self.accountID = accountID
        likedSongs = []; playlists = []; albums = []; pending = []; trackRevisions = [:]
        likesLoaded = false; playlistsLoaded = false; albumsLoaded = false
        songRevision = 0; playlistRevision = 0; albumRevision = 0; revision += 1
    }

    var writablePlaylists: [QQMusicLibraryPlaylist] { playlists.filter { $0.isOwned && !$0.isLiked && $0.directoryID > 0 } }
    func isOwnedPlaylist(_ id: String) -> Bool { playlists.contains { $0.id == id && $0.isOwned } }
    func isSubscribed(_ id: String, kind: QQMusicLibraryKind) -> Bool? {
        switch kind {
        case .playlist: playlistsLoaded ? playlists.contains { $0.id == id } : nil
        case .album: albumsLoaded ? albums.contains { $0.id == id } : nil
        }
    }
    func contentRevision(playlistID: String) -> Int {
        trackRevisions[playlistID, default: 0] + (playlists.contains { $0.id == playlistID && $0.isLiked } ? songRevision : 0)
    }

    func loadLikes(force: Bool = false) async throws {
        let token = try accountToken()
        if likesLoaded && !force { return }
        let task = likesTask ?? QQMusicLibraryRead(version: songRevision, task: Task { [accountID] in try await api.likedSongs(accountID: accountID) })
        likesTask = task
        defer { if token == generation && likesTask?.id == task.id { likesTask = nil } }
        let songs = try await task.task.value
        try check(token)
        guard task.version == songRevision else { throw CancellationError() }
        likedSongs = songs; likesLoaded = true
    }
    func loadPlaylists(force: Bool = false) async throws {
        let token = try accountToken()
        if playlistsLoaded && !force { return }
        let task = playlistsTask ?? QQMusicLibraryRead(version: playlistRevision, task: Task { [accountID] in try await api.libraryPlaylists(accountID: accountID) })
        playlistsTask = task
        defer { if token == generation && playlistsTask?.id == task.id { playlistsTask = nil } }
        let items = try await task.task.value
        try check(token)
        guard task.version == playlistRevision else { throw CancellationError() }
        var seen = Set<String>()
        playlists = items.filter { seen.insert($0.id).inserted }; playlistsLoaded = true
    }
    func loadAlbums(force: Bool = false) async throws {
        let token = try accountToken()
        if albumsLoaded && !force { return }
        let task = albumsTask ?? QQMusicLibraryRead(version: albumRevision, task: Task { [accountID] in try await api.libraryAlbums(accountID: accountID) })
        albumsTask = task
        defer { if token == generation && albumsTask?.id == task.id { albumsTask = nil } }
        let items = try await task.task.value
        try check(token)
        guard task.version == albumRevision else { throw CancellationError() }
        albums = items; albumsLoaded = true
    }

    func setSongLiked(mid: String, _ liked: Bool) async throws {
        let token = try accountToken()
        // Resolve the numeric ID and original type; never send the MID as songId.
        let song = try await api.song(mid: mid)
        try check(token)
        try await mutate("song/\(mid)") { try await self.api.setSongLiked(song, liked: liked, accountID: self.accountID ?? "") } commit: {
            self.likesTask = nil
            self.songRevision += 1
            self.likedSongs.removeAll { $0.mid == mid }
            if liked { self.likedSongs.insert(song, at: 0) }
        }
    }

    func togglePlaylist(_ collection: QQMusicCollection) async throws {
        let token = try accountToken()
        try await loadPlaylists()
        try check(token)
        if isOwnedPlaylist(collection.id) { return }
        let selected = playlists.contains { $0.id == collection.id }
        try await mutate("playlist/\(collection.id)") {
            try await self.api.setPlaylistSubscribed(id: collection.id, subscribed: !selected, accountID: self.accountID ?? "")
        } commit: {
            self.playlistsTask = nil
            self.playlistRevision += 1
            self.playlists.removeAll { $0.id == collection.id }
            if !selected {
                self.playlists.insert(.init(id: collection.id, title: collection.title, coverURL: collection.coverURL, isOwned: false), at: 0)
            }
        }
    }

    func toggleAlbum(_ collection: QQMusicCollection) async throws {
        let token = try accountToken()
        try await loadAlbums()
        try check(token)
        let selected = albums.contains { $0.id == collection.id }
        let album: QQMusicLibraryAlbum
        if let known = albums.first(where: { $0.id == collection.id }) { album = known }
        else { album = try await api.libraryAlbum(mid: collection.id) }
        try check(token)
        try await mutate("album/\(collection.id)") { try await self.api.setAlbumSubscribed(album, subscribed: !selected, accountID: self.accountID ?? "") } commit: {
            self.albumsTask = nil
            self.albumRevision += 1
            self.albums.removeAll { $0.id == collection.id }
            if !selected { self.albums.insert(album, at: 0) }
        }
    }

    func addSong(mid: String, to playlist: QQMusicLibraryPlaylist) async throws {
        let token = try accountToken()
        // A picker item from a previous account cannot be used after account changes.
        try await loadPlaylists()
        try check(token)
        guard let current = writablePlaylists.first(where: { $0.id == playlist.id && $0.directoryID == playlist.directoryID }) else { throw QQMusicError.invalidResponse }
        let song = try await api.song(mid: mid)
        try check(token)
        try await mutate("add/\(playlist.id)/\(mid)") { try await self.api.addSong(song, to: current, accountID: self.accountID ?? "") } commit: {
            self.trackRevisions[playlist.id, default: 0] += 1
        }
    }

    func unsubscribePlaylist(id: String) async throws {
        let token = try accountToken()
        try await loadPlaylists(); try check(token)
        guard let item = playlists.first(where: { $0.id == id }), !item.isOwned else { return }
        try await togglePlaylist(item.collection)
    }
    func unsubscribeAlbum(id: String) async throws {
        let token = try accountToken()
        try await loadAlbums(); try check(token)
        guard let item = albums.first(where: { $0.id == id }) else { return }
        try await toggleAlbum(item.collection)
    }

    private func accountToken() throws -> UUID {
        try Task.checkCancellation()
        guard accountID != nil else { throw QQMusicError.loginRequired }
        return generation
    }
    private func check(_ token: UUID) throws {
        try Task.checkCancellation()
        guard generation == token, accountID != nil else { throw CancellationError() }
    }
    private func mutate(_ key: String, request: () async throws -> Void, commit: () -> Void) async throws {
        let token = try accountToken()
        guard pending.insert(key).inserted else { return }
        defer { if generation == token { pending.remove(key) } }
        try await request()
        try check(token)
        commit(); revision += 1
    }
}

nonisolated private struct QQMusicLibraryRead<Value: Sendable> {
    let id = UUID()
    let version: Int
    let task: Task<Value, Error>
}
