// Resource mapping adapted from MeloX HomePageModels / HomePageResourceModels (GPL-3.0).
import Foundation

nonisolated struct NeteaseHomeFeed: Decodable {
    let blocks: [NeteaseHomeBlock]
    let hasMore: Bool?
    let cursor: String?
}
nonisolated struct NeteaseHomeBlock: Decodable, Identifiable {
    let blockCode: String
    let uiElement: NeteaseHomeElement?
    let creatives: [NeteaseHomeCreative]?
    // Verified from the physical device home feed: titles include the account name.
    var isRadarPlaylistBlock: Bool { blockCode == "HOMEPAGE_BLOCK_MGC_PLAYLIST" }
    var id: String { blockCode + "/" + (resources.first?.id ?? "") }
    var title: String { uiElement?.subTitle?.title ?? uiElement?.mainTitle?.title ?? "为你推荐" }
    var resources: [NeteaseHomeResource] {
        var seen = Set<String>()
        return (creatives ?? []).flatMap { $0.resources ?? [] }.filter { seen.insert($0.id).inserted }
    }
    var playlists: [NeteasePlaylist] { unique(resources.compactMap(\.playlist)) }
    var songs: [NeteaseSong] { unique(resources.compactMap(\.song)) }
    private func unique<T: Identifiable>(_ items: [T]) -> [T] {
        var seen = Set<T.ID>()
        return items.filter { seen.insert($0.id).inserted }
    }
}
nonisolated struct NeteaseHomeCreative: Decodable { let resources: [NeteaseHomeResource]? }
nonisolated struct NeteaseHomeElement: Decodable {
    struct Title: Decodable { let title: String? }
    struct Image: Decodable { let imageUrl: String? }
    let mainTitle: Title?
    let subTitle: Title?
    let image: Image?
}
nonisolated struct NeteaseHomeResource: Decodable, Identifiable {
    let resourceType: String?
    let resourceID: String?
    let uiElement: NeteaseHomeElement?
    let songData: NeteaseSong?
    let artists: [NeteaseArtist]
    var id: String { (resourceType ?? "") + "/" + (resourceID ?? songData.map { String($0.id) } ?? "") }
    enum CodingKeys: String, CodingKey { case resourceType, resourceId, uiElement, resourceExtInfo }
    private struct Extra: Decodable { let songData: NeteaseSong?; let song: NeteaseSong?; let artists: [NeteaseArtist]? }
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        resourceType = try c.decodeIfPresent(String.self, forKey: .resourceType)
        resourceID = (try? c.decode(String.self, forKey: .resourceId)) ?? (try? c.decode(Int.self, forKey: .resourceId)).map(String.init)
        uiElement = try? c.decode(NeteaseHomeElement.self, forKey: .uiElement)
        let extra = try? c.decode(Extra.self, forKey: .resourceExtInfo)
        songData = extra?.songData ?? extra?.song; artists = extra?.artists ?? []
    }
    var playlist: NeteasePlaylist? {
        guard ["list", "playlist"].contains(resourceType?.lowercased() ?? ""),
              let id = resourceID.flatMap(Int.init), id > 0 else { return nil }
        return NeteasePlaylist(id: id, name: uiElement?.mainTitle?.title ?? "播放列表", picUrl: uiElement?.image?.imageUrl,
                              coverImgUrl: nil, trackCount: nil, description: nil, tracks: nil, trackIds: nil)
    }
    var song: NeteaseSong? {
        if let songData, songData.id > 0 { return songData }
        guard resourceType?.lowercased() == "song", let id = resourceID.flatMap(Int.init), id > 0 else { return nil }
        let title = uiElement?.mainTitle?.title ?? "歌曲"
        return NeteaseSong(id: id, name: title, artists: artists,
                           album: .init(id: 0, name: "", picUrl: uiElement?.image?.imageUrl, artist: artists.first))
    }
}

nonisolated enum NeteaseRegion: String, CaseIterable, Identifiable {
    case all = "ALL", chinese = "ZH", western = "EA", japanese = "JP", korean = "KR"
    var id: Self { self }
    var title: String { switch self { case .all: "全部"; case .chinese: "华语"; case .western: "欧美"; case .japanese: "日语"; case .korean: "韩语" } }
    var areaID: Int { switch self { case .all: 0; case .chinese: 7; case .western: 96; case .japanese: 8; case .korean: 16 } }
}
