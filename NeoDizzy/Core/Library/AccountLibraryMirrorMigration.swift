import Foundation

// Compatibility for the original account-mirror.json format; no live platform dependencies.
extension AccountLibraryMirror {
    private struct LegacySnapshot: Codable {
        var neteaseUserID: Int?
        // 仅用于迁移旧版喜欢缓存，新喜欢状态存入 favorites.sqlite。
        var likedTracks: [Int: Track] = [:]
        var likedOrder: [Int] = []
        var neteaseCollections: [MirroredCollection] = []
        var dizzyLabUserID: Int?
        var dizzyLabAlbums: [MirroredCollection] = []
        var firstSeen: [String: Date] = [:]
        /// 歌手名 → 网易云歌手 ID，来自喜欢的歌的详情。
        var artistIDs: [String: Int] = [:]
        var artistAvatars: [Int: URL] = [:]
    }

    static func migrateLegacy(_ data: Data) -> Snapshot {
        guard let old = try? JSONDecoder().decode(LegacySnapshot.self, from: data) else { return Snapshot() }
        return Snapshot(providers: [
            "netease": State(account: old.neteaseUserID.map(String.init), collections: old.neteaseCollections,
                             legacyLikes: old.likedOrder.compactMap { old.likedTracks[$0] },
                             artistIDs: old.artistIDs.mapValues(String.init),
                             artistAvatars: Dictionary(uniqueKeysWithValues: old.artistAvatars.map { (String($0.key), $0.value) })),
            "dizzylab": State(account: old.dizzyLabUserID.map(String.init), collections: old.dizzyLabAlbums)
        ], firstSeen: old.firstSeen)
    }
}
