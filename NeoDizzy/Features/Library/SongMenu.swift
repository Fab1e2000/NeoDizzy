import SwiftUI
import UIKit

/// All entry points use the same actions; platforms supply capabilities, never menu layouts.
struct SongMenuConfiguration {
    var primary: [SongRowAction]
    var secondary: [SongRowAction]
    var artistTitle: String
    var artists: [SongRowAction]
    var extras: [SongRowAction]

    var nativeItems: [UIMenuElement] {
        func action(_ item: SongRowAction) -> UIAction {
            UIAction(title: item.title, image: UIImage(systemName: item.systemImage),
                     attributes: item.disabled ? [.disabled] : item.role == .destructive ? [.destructive] : []) { _ in item.perform() }
        }
        let quick = UIMenu(options: .displayInline, children: primary.map(action))
        quick.preferredElementSize = .medium
        var navigation: [UIMenuElement] = secondary.map(action)
        if artists.count == 1, let artist = artists.first {
            navigation.append(UIAction(title: artistTitle, image: UIImage(systemName: "person")) { _ in artist.perform() })
        } else if !artists.isEmpty {
            navigation.append(UIMenu(title: artistTitle, image: UIImage(systemName: "person"), children: artists.map(action)))
        }
        var result: [UIMenuElement] = [quick]
        if !navigation.isEmpty { result.append(UIMenu(options: .displayInline, children: navigation)) }
        if !extras.isEmpty { result.append(UIMenu(options: .displayInline, children: extras.map(action))) }
        return result
    }
}

struct SongMenuContents: View {
    let configuration: SongMenuConfiguration
    var body: some View {
        ControlGroup {
            ForEach(configuration.primary) { item in action(item) }
        }
        Section {
            ForEach(configuration.secondary) { item in action(item) }
            if configuration.artists.count == 1, let artist = configuration.artists.first {
                Button(configuration.artistTitle, systemImage: "person", action: artist.perform)
            } else if !configuration.artists.isEmpty {
                Menu(configuration.artistTitle, systemImage: "person") {
                    ForEach(configuration.artists) { item in action(item) }
                }
            }
        }
        if !configuration.extras.isEmpty {
            Section { ForEach(configuration.extras) { item in action(item) } }
        }
    }
    private func action(_ item: SongRowAction) -> some View {
        Button(item.title, systemImage: item.systemImage, role: item.role, action: item.perform)
            .disabled(item.disabled)
    }
}

/// Presentations live outside the menu, which is destroyed as soon as an action is selected.
struct SongMenuHost<Content: View>: View {
    let track: Track
    var play: (() -> Void)? = nil
    var extras: [SongRowAction] = []
    @ViewBuilder let content: (SongMenuConfiguration) -> Content
    @Environment(ModuleRegistry.self) private var modules
    @Environment(FavoritesStore.self) private var favorites
    @Environment(PlayerStore.self) private var player
    @Environment(OfflineLibraryStore.self) private var library
    @Environment(DownloadStore.self) private var downloads
    @Environment(\.openRoute) private var openRoute
    @State private var presentation = SongActionPresentation()
    @State private var albumNavigation = AlbumNavigationPreparation()
    @State private var showsDownloads = false
    @State private var editing: AudioTagEditTarget?

    var body: some View {
        content(configuration)
            .modifier(SongActionPresentationModifier(track: track, presentation: presentation))
            .sheet(isPresented: $showsDownloads) { DownloadQueueSheet() }
            .sheet(item: $editing) { AudioTagEditorSheet(target: $0) }
            .preparedAlbumNavigation(albumNavigation)
            .onChange(of: track.id) { albumNavigation.cancel() }
            .onChange(of: modules.descriptors) { albumNavigation.cancel() }
    }

    private var configuration: SongMenuConfiguration {
        let liked = favorites.contains(track)
        let available = track.localSource != nil || track.playbackProviderID.map { modules.contains(providerID: $0) } == true
        var primary: [SongRowAction] = []
        if let play {
            let current = player.currentTrack?.id == track.id
            let pauses = current && player.isPlaying
            primary.append(.init(id: "play", title: pauses ? "暂停" : "播放", systemImage: pauses ? "pause.fill" : "play.fill") {
                if current { player.togglePlayback() } else { play() }
            })
        }
        primary.append(.init(id: "favorite", title: liked ? "取消喜欢" : "喜欢", systemImage: liked ? "heart.fill" : "heart",
                             disabled: !available || favorites.pending.contains(FavoriteSong(track: track).id)) {
            presentation.toggleFavorite(track, favorites: favorites, modules: modules)
        })
        primary.append(.init(id: "playlist", title: "加入播放列表", systemImage: "text.badge.plus") { presentation.playlist = true })
        var secondary: [SongRowAction] = []
        if library.localFile(for: track) == nil,
           modules.songDownloadAction(for: track, downloads: downloads) != nil {
            let download = SongRowAction(id: "download", title: player.cachedQuality(for: track) == nil ? "下载" : "转为下载",
                                         systemImage: "arrow.down.circle") {
                if let provider = track.playbackProviderID, modules.requiresLogin(providerID: provider) {
                    presentation.login = true
                    return
                }
                // Resolve again at selection time: a disabled/removed module cannot receive new work.
                guard let action = modules.songDownloadAction(for: track, downloads: downloads) else { return }
                action.perform()
                showsDownloads = true
            }
            if play == nil { primary.append(download) } else { secondary.append(download) }
        }
        let controller = PlayerArtistMenuController()
        controller.bind(track: track, modules: modules, open: { openRoute($0) })
        let artists = available ? controller.destinations().enumerated().map { index, destination in
            SongRowAction(id: "artist/\(index)", title: destination.name, systemImage: "person") {
                guard track.localSource != nil || track.playbackProviderID.map({ modules.contains(providerID: $0) }) == true else { return }
                openRoute(destination.route)
            }
        } : []
        if albumRoute != nil {
            secondary.append(.init(id: "album", title: "查看专辑", systemImage: "square.stack") {
                guard let destination = albumRoute else { return }
                if let route = albumNavigation.begin(destination, artworkURL: track.coverURL) { openRoute(route) }
            })
        }
        var contextual = extras
        if !extras.contains(where: { $0.id == "edit" }), let file = library.localFile(for: track) {
            contextual.append(.init(id: "edit", title: "编辑音乐标签", systemImage: "pencil") {
                editing = AudioTagEditTarget(track: track, url: file)
            })
        }
        return .init(primary: primary, secondary: secondary,
                     artistTitle: modules.artistNavigation(for: track) == .single ? "查看社团" : "查看艺人",
                     artists: artists, extras: contextual)
    }

    private var albumRoute: AppRoute? {
        if let source = track.localSource {
            return .localAlbum(id: library.localAlbum(for: track)?.id ?? source.albumID)
        }
        return modules.songAlbumRoute(for: track)
    }
}
