import Foundation
import Observation

@Observable
final class NeteaseStore {
    let api: NeteaseAPI
    let library: NeteaseLibrary
    let radio: NeteaseRadioSession
    let reporter: NeteasePlaybackReporter
    var playbackSettings: NeteasePlaybackSettings { api.playbackSettings }
    private(set) var profile: NeteaseProfile?
    private(set) var revision = 0
    var showsAccount = false
    var showsLogin = false
    var accountChanged: (() -> Void)?
    private let credentialKey = "netease.session.v1"

    init(api injectedAPI: NeteaseAPI? = nil) {
        let client = injectedAPI?.client ?? NeteaseClient()
        let api = injectedAPI ?? NeteaseAPI(client: client)
        self.api = api
        reporter = NeteasePlaybackReporter(api: api)
        library = NeteaseLibrary(api: api)
        radio = NeteaseRadioSession { try await api.radio().map(\.track) }
        if injectedAPI == nil, let data = KeychainStore.data(for: credentialKey), let saved = try? JSONDecoder().decode(Session.self, from: data) {
            client.cookie = saved.cookie
            profile = saved.profile
        }
        library.reset(userID: profile?.userId)
    }
    func heartModeSongs() async throws -> (songs: [Track], playlistID: Int) {
        let revision = revision
        try await library.loadLikes()
        try await library.loadPlaylists()
        guard self.revision == revision else { throw CancellationError() }
        guard let seed = library.orderedLikedIDs.randomElement(),
              let playlist = library.playlists.first(where: { $0.specialType == 5 && $0.creator?.userId == profile?.userId }) else {
            throw NeteasePlaybackError.noLikes
        }
        let songs = try await api.intelligenceSongs(seedID: seed, playlistID: playlist.id)
        try Task.checkCancellation()
        guard self.revision == revision else { throw CancellationError() }
        return (songs.map(\.track), playlist.id)
    }
    private struct Session: Codable { let cookie: String; let profile: NeteaseProfile }
    func login(cookie: String) async throws {
        let previous = api.client.cookie
        api.client.cookie = cookie
        do {
            let account = try await api.profile()
            try Task.checkCancellation()
            reporter.reset()
            profile = account
            KeychainStore.set(try JSONEncoder().encode(Session(cookie: cookie, profile: account)), for: credentialKey)
            library.reset(userID: account.userId)
            radio.reset()
            revision += 1
            accountChanged?()
            showsLogin = false
        } catch { api.client.cookie = previous; throw error }
    }
    func logout() {
        reporter.reset()
        library.reset(userID: nil)
        radio.reset()
        api.client.cookie = ""
        profile = nil
        KeychainStore.set(nil, for: credentialKey)
        revision += 1
        accountChanged?()
        showsAccount = false
    }
}
