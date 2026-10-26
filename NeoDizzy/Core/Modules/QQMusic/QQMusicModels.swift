import Foundation

nonisolated struct QQMusicCredential: Codable, Equatable, Sendable {
    var musicID: String
    var musicKey: String
    var loginType: Int = 2
    var nickname: String? = nil
    var avatarURL: URL? = nil
}

nonisolated struct QQMusicSong: Identifiable, Hashable, Sendable {
    let id: String
    let mid: String
    let title: String
    let artist: String
    let albumMid: String
    let albumTitle: String
    let coverURL: URL?
    let duration: TimeInterval?
    let songType: Int
    let trackNumber: Int?
    let discNumber: Int?
    let singers: [QQMusicArtist]
    var track: Track {
        Track(discID: albumMid, number: mid, title: title, artists: artist,
              albumTitle: albumTitle, coverURL: coverURL, duration: duration,
              remoteSource: RemoteTrackSource(providerID: "qqmusic", itemID: mid))
    }

    init(json: [String: Any]) throws {
        guard let mid = json["mid"] as? String, !mid.isEmpty,
              let title = (json["title"] ?? json["name"]) as? String else { throw QQMusicError.invalidResponse }
        self.mid = mid
        id = (json["id"] as? String).flatMap { $0.isEmpty ? nil : $0 } ?? (json["id"] as? NSNumber)?.stringValue ?? mid
        self.title = title
        songType = json["type"] as? Int ?? 0
        trackNumber = (json["index_album"] as? Int).flatMap { $0 > 0 ? $0 : nil }
        discNumber = (json["index_cd"] as? Int).flatMap { $0 > 0 ? $0 : nil }
        singers = (json["singer"] as? [[String: Any]] ?? []).compactMap { try? QQMusicArtist(json: $0) }
        artist = (json["singer"] as? [[String: Any]] ?? []).compactMap { $0["name"] as? String }.joined(separator: " / ")
        let album = json["album"] as? [String: Any] ?? [:]
        albumMid = album["mid"] as? String ?? ""
        albumTitle = (album["title"] ?? album["name"]) as? String ?? ""
        coverURL = Self.cover(albumMid: albumMid)
        duration = (json["interval"] as? NSNumber)?.doubleValue
    }

    static func cover(albumMid: String) -> URL? {
        guard !albumMid.isEmpty, albumMid.allSatisfy({ $0.isASCII && ($0.isLetter || $0.isNumber) }) else { return nil }
        return URL(string: "https://y.gtimg.cn/music/photo_new/T002R500x500M000\(albumMid).jpg")
    }
}

nonisolated struct QQMusicCollection: Identifiable, Sendable {
    let id: String
    let title: String
    let coverURL: URL?
    var songs: [QQMusicSong] = []
    var detailDescription = ""
}

nonisolated struct QQMusicChartGroup: Identifiable, Sendable {
    let id: String
    let title: String
    let charts: [QQMusicCollection]
}

nonisolated struct QQMusicPlaylistPage: Sendable {
    let items: [QQMusicCollection]
    let nextCursor: Int?
}

nonisolated struct QQMusicRadarPage: Sendable {
    let items: [QQMusicSong]
    let hasMore: Bool
}

nonisolated enum QQMusicError: LocalizedError {
    case disabled, invalidResponse, server(Int), unavailable, loginRequired
    var errorDescription: String? {
        switch self {
        case .disabled: "QQ 音乐模块已停用。"
        case .invalidResponse: "QQ 音乐返回的数据无法识别，请稍后重试。"
        case .server(let code): "QQ 音乐请求失败（\(code)）。"
        case .unavailable: "这首歌曲暂时无法播放，可能需要会员、购买或受地区限制。"
        case .loginRequired: "请先登录 QQ 音乐，再尝试播放。"
        }
    }
}

nonisolated enum QQMusicSearchKind: Int, CaseIterable, Hashable, Sendable {
    case songs = 0, albums = 2, artists = 1, playlists = 3
    var title: String {
        switch self { case .songs: "歌曲"; case .albums: "专辑"; case .artists: "歌手"; case .playlists: "播放列表" }
    }
    var responseKey: String {
        switch self { case .songs: "item_song"; case .albums: "item_album"; case .artists: "singer"; case .playlists: "item_songlist" }
    }
}

nonisolated struct QQMusicAlbum: Identifiable, Hashable, Sendable {
    let id: String
    let title: String
    let artist: String
    let coverURL: URL?
    let releaseDate: String

    init(json: [String: Any]) throws {
        guard let mid = (json["mid"] ?? json["albumMid"] ?? json["albummid"]) as? String, !mid.isEmpty,
              let name = (json["title"] ?? json["name"] ?? json["albumName"]) as? String else { throw QQMusicError.invalidResponse }
        id = mid; title = QQMusicText.clean(name)
        let singers = (json["singer_list"] ?? json["singers"]) as? [[String: Any]] ?? []
        artist = QQMusicText.clean((json["singerName"] ?? json["singer"]) as? String ?? singers.compactMap { $0["name"] as? String }.joined(separator: " / "))
        coverURL = QQMusicText.url(json["pic"]) ?? QQMusicSong.cover(albumMid: mid)
        releaseDate = (json["publishDate"] ?? json["publish_date"] ?? json["release_time"]) as? String ?? ""
    }
}

nonisolated struct QQMusicArtist: Identifiable, Hashable, Sendable {
    let id: String
    let name: String
    let coverURL: URL?
    let subtitle: String
    var biography = ""

    init(json: [String: Any]) throws {
        guard let mid = (json["mid"] ?? json["singerMID"] ?? json["singerMid"] ?? json["singer_mid"]) as? String, !mid.isEmpty,
              let name = (json["name"] ?? json["singerName"] ?? json["singer_name"]) as? String else { throw QQMusicError.invalidResponse }
        id = mid; self.name = QQMusicText.clean(name)
        subtitle = QQMusicText.clean((json["subtitle"] ?? json["other_name"]) as? String ?? "")
        coverURL = QQMusicText.url(json["singerPic"] ?? json["singer_pic"]) ?? Self.cover(mid: mid)
    }

    static func cover(mid: String) -> URL? {
        guard !mid.isEmpty, mid.allSatisfy({ $0.isASCII && ($0.isLetter || $0.isNumber) }) else { return nil }
        return URL(string: "https://y.gtimg.cn/music/photo_new/T001R500x500M000\(mid).jpg")
    }
}

nonisolated struct QQMusicBrowsePage: Sendable {
    var songs: [QQMusicSong] = []
    var albums: [QQMusicAlbum] = []
    var artists: [QQMusicArtist] = []
    var playlists: [QQMusicCollection] = []
    var nextPage: Int?
    var nextOffset: Int?
}

nonisolated enum QQMusicText {
    static func detailDescription(_ json: [String: Any]) -> String {
        for key in ["desc", "description", "intro"] {
            guard let text = json[key] as? String else { continue }
            let plain = clean(text
                .replacingOccurrences(of: "(?i)<br\\s*/?>|</(?:p|div)\\s*>", with: "\n", options: .regularExpression)
                .replacingOccurrences(of: "<[^>]+>", with: "", options: .regularExpression))
                .replacingOccurrences(of: "&nbsp;", with: " ")
                .replacingOccurrences(of: "&#39;", with: "'")
                .replacingOccurrences(of: "&apos;", with: "'")
                .trimmingCharacters(in: .whitespacesAndNewlines)
            if !plain.isEmpty { return plain }
        }
        return ""
    }

    static func clean(_ text: String) -> String {
        text.replacingOccurrences(of: "</?em>", with: "", options: .regularExpression)
            .replacingOccurrences(of: "&amp;", with: "&").replacingOccurrences(of: "&quot;", with: "\"")
            .replacingOccurrences(of: "&lt;", with: "<").replacingOccurrences(of: "&gt;", with: ">")
    }
    static func url(_ value: Any?) -> URL? {
        guard let text = value as? String, !text.isEmpty,
              let url = URL(string: text.replacingOccurrences(of: "http://", with: "https://")),
              url.scheme == "https", url.host != nil else { return nil }
        return url
    }
}
