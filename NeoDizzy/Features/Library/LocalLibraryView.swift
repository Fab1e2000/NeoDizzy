import SwiftUI
import UniformTypeIdentifiers

struct LocalLibraryView: View {
    @Environment(OfflineLibraryStore.self) private var library

    private struct AlbumItem: Identifiable {
        let id: String
        let title: String
        let artist: String
        let coverURL: URL?
        let count: Int
        let route: AppRoute
    }
    private var items: [AlbumItem] {
        let local = library.localAlbums.map {
            AlbumItem(id: "local/\($0.id)", title: $0.title, artist: $0.artist, coverURL: $0.coverURL,
                      count: $0.tracks.count, route: .localAlbum(id: $0.id))
        }
        return local.sorted { $0.title.localizedStandardCompare($1.title) == .orderedAscending }
    }

    var body: some View {
        MainTabPage(tab: .localLibrary, onRefresh: { await library.scan() }) {
            if library.isScanning { ProgressView().accessibilityLabel("正在扫描本地音乐") }
            if let issue = library.issue {
                Label(issue, systemImage: "exclamationmark.triangle")
                    .font(.caption).foregroundStyle(DizzyPalette.accent)
            }
            if items.isEmpty {
                ContentUnavailableView("还没有本地专辑", systemImage: "music.note.list",
                                       description: Text("在「我的 → 设置 → 扫描目录」添加音乐文件夹。下载的专辑也会自动显示在这里。"))
            } else {
                LazyVGrid(columns: DizzyGrid.columns, alignment: .leading, spacing: 22) {
                    ForEach(items) { album in
                        NavigationLink(value: album.route) {
                            VStack(alignment: .leading, spacing: 6) {
                                ArtworkImage(url: album.coverURL)
                                Text(album.title).font(.subheadline.weight(.semibold)).lineLimit(2)
                                Text(album.artist).font(.caption).foregroundStyle(DizzyPalette.mutedText).lineLimit(1)
                                Text("\(album.count) 首").font(.caption).foregroundStyle(DizzyPalette.mutedText)
                            }
                            .multilineTextAlignment(.leading)
                            .contentShape(.rect)
                            .accessibilityElement(children: .combine)
                            .prefetchAlbumArtwork(url: album.coverURL)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
    }
}

struct LocalAlbumDetailView: View {
    let id: String
    @State private var editing: AudioTagEditTarget?
    @State private var batchAlbum: LocalAlbum?
    @Environment(OfflineLibraryStore.self) private var library
    @Environment(PlayerStore.self) private var player

    var body: some View {
        Group {
            if let album = library.localAlbum(id: id) {
                AlbumDetailScrollView(artworkURL: album.coverURL) {
                    LazyVStack(alignment: .leading, spacing: 0) {
                        AlbumHero(artworkURL: album.coverURL, title: album.title,
                                  metadata: "\(album.tracks.count) 首") {
                            Text(album.artist)
                        } actions: {
                            AlbumPlaybackActions(isEmpty: album.tracks.isEmpty, batchEdit: { batchAlbum = album }) { shuffled in
                                guard !album.tracks.isEmpty else { return }
                                player.play(album.tracks, startAt: shuffled ? Int.random(in: album.tracks.indices) : 0)
                                if player.isShuffled != shuffled { player.toggleShuffle() }
                            }
                        }
                        ForEach(Array(Set(album.entries.map(\.discNumber))).sorted(), id: \.self) { disc in
                            if Set(album.entries.map(\.discNumber)).count > 1 {
                                Text("Disc \(disc)").font(.headline).padding(.vertical, 12)
                            }
                            ForEach(album.entries.filter { $0.discNumber == disc }, id: \.track.id) { entry in
                                AlbumTrackRow(track: entry.track, editTags: {
                                    editing = AudioTagEditTarget(track: entry.track, url: entry.fileURL)
                                }) {
                                    if let index = album.tracks.firstIndex(where: { $0.id == entry.track.id }) {
                                        player.play(album.tracks, startAt: index)
                                    }
                                }
                                .padding(.horizontal, -20)
                            }
                        }
                    }
                    .padding(.horizontal, 20).padding(.bottom, 32)
                }
            } else {
                ContentUnavailableView("找不到本地专辑", systemImage: "folder.badge.questionmark",
                                       description: Text("请检查扫描目录授权和音乐文件，然后重新扫描。"))
            }
        }
        .dizzyPageBackground()
        .sheet(item: $editing) { AudioTagEditorSheet(target: $0) }
        .sheet(item: $batchAlbum) { BatchAudioTagEditorSheet(album: $0) }
        .navigationTitle("")
        .toolbar(.visible, for: .navigationBar)
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(.hidden, for: .navigationBar)
    }
}
