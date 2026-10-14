import Foundation

nonisolated struct NeteaseArtist: Decodable, Identifiable, Hashable, Sendable {
    let id: Int
    let name: String
    var picUrl: String? = nil
    var img1v1Url: String? = nil
    var briefDesc: String? = nil
    var artworkURL: URL? { NeteaseArtwork.url(picUrl ?? img1v1Url) }
}
nonisolated struct NeteaseAlbum: Decodable, Identifiable, Hashable, Sendable {
    let id: Int
    let name: String
    let picUrl: String?
    let artist: NeteaseArtist?
    var artworkURL: URL? { NeteaseArtwork.url(picUrl) }
}
nonisolated struct NeteasePlaylist: Decodable, Identifiable, Hashable, Sendable {
    let id: Int
    let name: String
    let picUrl: String?
    let coverImgUrl: String?
    let trackCount: Int?
    let description: String?
    let tracks: [NeteaseSong]?
    let trackIds: [NeteaseSongID]?
    var subscribed: Bool? = nil
    var creator: NeteaseProfile? = nil
    var specialType: Int? = nil
    var updateTime: Int? = nil
    var artworkURL: URL? { NeteaseArtwork.url(coverImgUrl ?? picUrl) }
}
nonisolated struct NeteaseSongID: Decodable, Hashable, Sendable { let id: Int }
nonisolated struct NeteaseProfile: Codable, Hashable, Sendable {
    let userId: Int
    let nickname: String
    let avatarUrl: String?
}
nonisolated struct NeteaseSong: Decodable, Identifiable, Hashable, Sendable {
    let id: Int
    let name: String
    let artists: [NeteaseArtist]
    let album: NeteaseAlbum?
    let duration: Double?
    init(id: Int, name: String, artists: [NeteaseArtist], album: NeteaseAlbum?, duration: Double? = nil) {
        self.id = id; self.name = name; self.artists = artists; self.album = album; self.duration = duration
    }
    enum CodingKeys: String, CodingKey { case id, name, artists, ar, album, al, duration, dt }
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(Int.self, forKey: .id)
        name = try c.decode(String.self, forKey: .name)
        artists = try c.decodeIfPresent([NeteaseArtist].self, forKey: .ar) ?? c.decodeIfPresent([NeteaseArtist].self, forKey: .artists) ?? []
        album = try c.decodeIfPresent(NeteaseAlbum.self, forKey: .al) ?? c.decodeIfPresent(NeteaseAlbum.self, forKey: .album)
        duration = try c.decodeIfPresent(Double.self, forKey: .dt) ?? c.decodeIfPresent(Double.self, forKey: .duration)
    }
    var track: Track {
        Track(discID: String(album?.id ?? 0), number: String(id), title: name,
              artists: artists.map(\.name).joined(separator: " / "), albumTitle: album?.name ?? "",
              coverURL: album?.artworkURL, duration: duration.map { $0 / 1000 },
              remoteSource: RemoteTrackSource(providerID: "netease", itemID: String(id)))
    }
}
nonisolated enum NeteaseArtwork {
    static func url(_ text: String?) -> URL? {
        guard let text, var c = URLComponents(string: text), let host = c.host,
              host.hasSuffix(".music.126.net") || host == "music.126.net" else { return nil }
        c.scheme = "https"
        c.queryItems = [URLQueryItem(name: "param", value: "640y640")]
        return c.url
    }
}
