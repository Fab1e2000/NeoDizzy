import SwiftUI

struct FavoriteButton: View {
    let track: Track
    var playerStyle = false
    var presentation: SongActionPresentation? = nil
    @Environment(FavoritesStore.self) private var favorites
    @Environment(NeteaseStore.self) private var netease: NeteaseStore?
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
            if track.remoteSource?.providerID == "netease", netease?.profile == nil {
                actionPresentation.login = true
                return
            }
            let target = !liked
            Task {
                do { try await favorites.setLiked(track, target) }
                catch is CancellationError { }
                catch { actionPresentation.failure = error.localizedDescription }
            }
        } label: {
            if playerStyle {
                Image(systemName: liked ? "heart.fill" : "heart")
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(liked ? DizzyPalette.accentOnDark : .white)
                    .frame(width: 44, height: 44)
                    .background(.white.opacity(0.15), in: .circle)
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
    var body: some View {
        let songs = favorites.songs
        let tracks = songs.map(\.track)
        let artwork = songs.first?.track.coverURL
        AlbumDetailScrollView(artworkURL: artwork) {
            LazyVStack(alignment: .leading, spacing: 0) {
                AlbumHero(artworkURL: artwork, title: "喜欢", metadata: "\(songs.count) 首歌曲") {
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
                    AlbumTrackRow(track: song.track, displayNumber: String(index + 1)) {
                        player.play(tracks, startAt: index)
                    }.padding(.horizontal, -20)
                }
                ForEach(favorites.errors.keys.sorted(), id: \.self) { key in
                    Text("\(LibraryOrigin(providerID: key)?.label ?? key)：\(favorites.errors[key] ?? "")")
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
