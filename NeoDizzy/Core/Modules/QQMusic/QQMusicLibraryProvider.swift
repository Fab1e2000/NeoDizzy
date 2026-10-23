import Foundation

extension LibraryProviderRegistry {
    func registerQQMusic(_ store: QQMusicStore) {
        register("qqmusic", provider: Provider(
            title: "QQ 音乐",
            onlineSongs: { item in
                let revision = store.revision
                guard store.active else { throw CancellationError() }
                let collection: QQMusicCollection
                switch item.kind {
                case "playlist": collection = try await store.api.playlist(id: item.itemID)
                case "album": collection = try await store.api.album(mid: item.itemID)
                default: throw ProviderError.unavailable
                }
                try Task.checkCancellation()
                guard store.active, store.revision == revision else { throw CancellationError() }
                return collection.songs.map(\.track)
            },
            exportSettings: { ["quality": store.playbackSettings.quality.rawValue] },
            applySettings: { values in
                if let quality = values["quality"].flatMap(QQMusicQuality.init(rawValue:)) {
                    store.playbackSettings.quality = quality
                }
            },
            exportCredential: {
                guard let credential = store.credential, let data = try? JSONEncoder().encode(credential) else { return nil }
                return String(data: data, encoding: .utf8)
            },
            restoreCredential: { value in
                guard store.credential == nil else { return .alreadySignedIn }
                guard let credential = try? JSONDecoder().decode(QQMusicCredential.self, from: Data(value.utf8)),
                      !credential.musicID.isEmpty, credential.musicID != "0", !credential.musicKey.isEmpty else { return .expired }
                do { try await store.restoreCredential(credential); return .restored }
                catch { return .expired }
            }))
    }
}
