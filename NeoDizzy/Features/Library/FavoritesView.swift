import SwiftUI

struct FavoriteButton: View {
    let track: Track
    var playerStyle = false
    var presentation: SongActionPresentation? = nil
    @Environment(FavoritesStore.self) private var favorites
    @Environment(ModuleRegistry.self) private var modules
    @State private var ownPresentation = SongActionPresentation()
    private var actionPresentation: SongActionPresentation { presentation ?? ownPresentation }
    private var liked: Bool { favorites.contains(track) }
    var body: some View {
        if presentation == nil {
            button.modifier(SongActionPresentationModifier(track: track, presentation: ownPresentation))
        } else {
            button
        }
    }
    private var button: some View {
        Button {
            actionPresentation.toggleFavorite(track, favorites: favorites, modules: modules)
        } label: {
            if playerStyle {
                Image(systemName: liked ? "heart.fill" : "heart")
                    .resizable()
                    .scaledToFit()
                    .frame(width: 19.14, height: 19.14)
                    .foregroundStyle(liked ? DizzyPalette.accentOnDark : .white)
                    .frame(width: 44, height: 44)
            } else {
                Label(liked ? "取消喜欢" : "喜欢", systemImage: liked ? "heart.fill" : "heart")
            }
        }
        .disabled(favorites.pending.contains(FavoriteSong(track: track).id))
        .accessibilityLabel(liked ? "取消喜欢" : "喜欢")
    }
}

struct FavoritesPage: View {
    @Environment(FavoritesStore.self) private var favorites
    @Environment(PlayerStore.self) private var player
    @Environment(OfflineLibraryStore.self) private var library
    @Environment(ModuleRegistry.self) private var modules
    var body: some View {
        let songs = favorites.songs
        let tracks = songs.map(\.track)
        let artwork = songs.first?.track.coverURL
        AlbumDetailScrollView(artworkURL: artwork) {
            LazyVStack(alignment: .leading, spacing: 0) {
                AlbumHero(artworkURL: artwork, title: "喜欢的歌", metadata: "\(songs.count) 首歌曲") {
                    EmptyView()
                } actions: {
                    AlbumPlaybackActions(isEmpty: tracks.isEmpty) { shuffled in
                        guard !tracks.isEmpty else { return }
                        player.play(tracks, startAt: shuffled ? Int.random(in: tracks.indices) : 0)
                        if player.isShuffled != shuffled { player.toggleShuffle() }
                    }
                }
                .id(artwork)
                if songs.isEmpty && !favorites.syncing.isEmpty {
                    ContentSkeleton(layout: .songs)
                } else if songs.isEmpty {
                    ContentUnavailableView("还没有喜欢的音乐", systemImage: "heart",
                        description: Text("在歌曲菜单或播放器中选择「喜欢」，就会出现在这里。"))
                }
                ForEach(songs.enumerated(), id: \.element.id) { index, song in
                    let downloaded = library.localFile(for: song.track) != nil
                    SongRow(track: song.track, isDownloaded: downloaded) {
                        player.play(tracks, startAt: index)
                    }
                }
                ForEach(favorites.errors.keys.sorted(), id: \.self) { key in
                    Text("\(modules.origin(providerID: key)?.label ?? key)：\(favorites.errors[key] ?? "")")
                        .font(.footnote).foregroundStyle(.secondary)
                }
                if !favorites.errors.isEmpty {
                    Button("重试同步") { Task { await favorites.refresh() } }
                }
            }.padding(.horizontal, 20).padding(.bottom, 32)
        }
        .safeAreaPadding(.top, 5)
        .navigationTitle("")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar(.visible, for: .navigationBar)
        .toolbarBackground(.hidden, for: .navigationBar)
        .refreshable { await favorites.refresh() }
    }

}
