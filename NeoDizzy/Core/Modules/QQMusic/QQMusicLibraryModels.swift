import Foundation

nonisolated enum QQMusicLibraryKind: String, Sendable { case playlist, album }

/// Public playlist identity is its TID; writes to an owned list additionally need its dirId.
nonisolated struct QQMusicLibraryPlaylist: Identifiable, Sendable {
    let id: String
    let directoryID: Int
    let title: String
    let coverURL: URL?
    let isOwned: Bool
    let songCount: Int
    var isLiked: Bool { isOwned && directoryID == 201 }
    var collection: QQMusicCollection { .init(id: id, title: title, coverURL: coverURL) }

    init(id: String, directoryID: Int = 0, title: String, coverURL: URL? = nil, isOwned: Bool, songCount: Int = 0) {
        self.id = id; self.directoryID = directoryID; self.title = title
        self.coverURL = coverURL; self.isOwned = isOwned; self.songCount = songCount
    }

    init(json: [String: Any], owned: Bool) throws {
        guard let id = QQMusicClient.identifier(json["tid"] ?? json["id"] ?? json["dissid"]), id != "0",
              let title = (json["title"] ?? json["dirName"] ?? json["name"] ?? json["dissname"]) as? String else { throw QQMusicError.invalidResponse }
        self.init(id: id, directoryID: (json["dirId"] ?? json["dirid"]) as? Int ?? 0, title: title,
                  coverURL: QQMusicClient.url(json["picUrl"] ?? json["picurl"] ?? json["cover"] ?? json["logo"]),
                  isOwned: owned, songCount: (json["songnum"] ?? json["songNum"] ?? json["song_cnt"]) as? Int ?? 0)
    }
}

nonisolated struct QQMusicLibraryAlbum: Identifiable, Sendable {
    /// MID is the stable route identity; numericID is only used in account writes.
    let id: String
    let numericID: Int64
    let title: String
    let coverURL: URL?
    var collection: QQMusicCollection { .init(id: id, title: title, coverURL: coverURL) }

    init(json: [String: Any]) throws {
        guard let mid = (json["mid"] ?? json["albumMid"] ?? json["albumMID"] ?? json["albummid"]) as? String, !mid.isEmpty,
              let value = QQMusicClient.identifier(json["id"] ?? json["albumID"]), let numericID = Int64(value), numericID > 0,
              let title = (json["title"] ?? json["name"] ?? json["albumName"]) as? String else { throw QQMusicError.invalidResponse }
        id = mid; self.numericID = numericID; self.title = title; coverURL = QQMusicSong.cover(albumMid: mid)
    }
}
