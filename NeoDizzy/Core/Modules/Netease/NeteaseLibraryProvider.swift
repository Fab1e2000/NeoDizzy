import Foundation

extension LibraryProviderRegistry {
    func registerNetease(_ store: NeteaseStore, mirror: AccountLibraryMirror) {
        register("netease", provider: Provider(
            title: "网易云音乐",
            onlineSongs: { item in
                let revision = store.revision
                guard let id = Int(item.itemID) else { throw ProviderError.unavailable }
                let tracks: [Track]
                if item.kind == "playlist" {
                    let playlist = try await store.api.playlist(id)
                    let ids = playlist.trackIds?.map(\.id) ?? playlist.tracks?.map(\.id) ?? []
                    guard !ids.isEmpty || (playlist.trackCount ?? 0) == 0 else { throw ProviderError.incomplete }
                    var songs: [NeteaseSong] = []
                    for start in stride(from: 0, to: ids.count, by: 400) {
                        try Task.checkCancellation()
                        songs += try await store.api.songs(Array(ids[start..<min(start + 400, ids.count)]))
                    }
                    guard songs.count == ids.count else { throw ProviderError.incomplete }
                    tracks = songs.map(\.track)
                } else if item.kind == "album" { tracks = try await store.api.album(id).1.map(\.track) }
                else { throw ProviderError.unavailable }
                guard store.revision == revision else { throw CancellationError() }
                return tracks
            },
            exportSettings: { ["quality": store.playbackSettings.quality.rawValue] },
            applySettings: { values in
                if let quality = values["quality"].flatMap(NeteaseQuality.init(rawValue:)) { store.playbackSettings.quality = quality }
            },
            exportCredential: {
                let cookie = store.api.client.cookie
                guard store.profile != nil, NeteaseClient.cookieValues(cookie)["MUSIC_U"] != nil else { return nil }
                return cookie
            },
            restoreCredential: { cookie in
                guard store.profile == nil else { return .alreadySignedIn }
                do { try await store.login(cookie: cookie); return .restored }
                catch { return .expired }
            },
            artistLookupKey: { name in
                "\(store.revision)/\(mirror.neteaseAccountID ?? 0)/\(mirror.neteaseArtistID(named: name) ?? 0)/\(name)"
            },
            artistAvatar: { name in mirror.neteaseArtistID(named: name).flatMap(mirror.artistAvatar) },
            loadArtistAvatar: { name in
                if let id = mirror.neteaseArtistID(named: name) { await mirror.loadArtistAvatar(id, api: store.api) }
            }))
    }
}
