import Foundation

/// 资料库里的网易云内容就是账号本身：加入 = 喜欢 / 收藏，移除 = 取消。这些操作都是幂等的。
extension NeteaseLibrary {
    func setSongLiked(_ id: Int, _ liked: Bool) async throws {
        try await loadLikes()
        if likedIDs.contains(id) != liked { try await toggleLike(id) }
    }

    func unsubscribePlaylist(id: Int) async throws {
        try await loadPlaylists()
        guard let playlist = playlists.first(where: { $0.id == id }), isSubscribed(playlist) == true else { return }
        try await togglePlaylist(playlist)
    }

    func unsubscribeAlbum(id: Int) async throws {
        try await loadAlbums()
        guard let album = albums.first(where: { $0.id == id }) else { return }
        try await toggleAlbum(album)
    }
}
