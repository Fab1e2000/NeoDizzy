import SwiftUI

struct ModuleDescriptor: Identifiable, Equatable {
    let id: ModuleID
    let title: String
    let systemImage: String
    /// 这个标签页及其推入页面使用的主题色；没有自己品牌色的模块用中性的黑色。
    var accent: AccentPalette = .neutral
    /// 可选的模块自有模板图资源；不提供时使用系统图标。
    var imageAsset: String? = nil

    var icon: Image {
        if let imageAsset {
            Image(imageAsset).renderingMode(.template)
        } else {
            Image(systemName: systemImage)
        }
    }
}

/// Optional account capability; modules with accounts get a row in the global settings.
struct ModuleAccountEntry {
    let title: String
    let avatarURL: URL?
    var isSignedIn = false
}

/// Provider-owned artist identity and destination, usable by the shared player.
struct PlayerArtistDestination: Identifiable {
    let name: String
    let route: AppRoute
    var id: AppRoute { route }
}

/// 播放器里点作者名时的去处。
enum PlayerArtistNavigation {
    /// 每位作者各自的艺人页（作者名按本地拆分，多位时弹菜单）。
    case perArtist
    /// 整首歌只有一个去处（比如来源只提供社团页），点了直接进入，不按作者名拆分。
    case single
}

/// A compiled-in feature plugs into these slots; the host never switches on provider IDs.
@MainActor
protocol AppModule {
    var descriptor: ModuleDescriptor { get }
    var libraryOrigin: LibraryOrigin { get }
    var downloadsWholeAlbums: Bool { get }
    var accountEntry: ModuleAccountEntry? { get }
    func openAccount()
    func dismissAccount()
    func deactivate()
    func rootView() -> AnyView
    func destination(for route: AppRoute) -> AnyView?
    func install(in content: AnyView) -> AnyView
    func songAlbumRoute(for track: Track) -> AppRoute?
    func artistDestinations(for track: Track) async throws -> [PlayerArtistDestination]
    var artistNavigation: PlayerArtistNavigation { get }
    func handleURL(_ url: URL, host: ModuleHost) -> Bool
    /// 统一搜索里这个模块的一组结果（含标题和「查看全部」）；没有搜索能力的模块返回 nil。
    func searchSection(query: String) -> AnyView?
    func loginView() -> AnyView?
    /// Platform-owned sections embedded in the shared playlist sheet; nil means unsupported.
    func playlistPicker(for track: Track) -> AnyView?
    func collectionRoute(kind: String, itemID: String) -> AppRoute?
    func collectionRemoval(for item: MirroredCollection) -> LibraryRemoval?
    func removeCollection(kind: String, itemID: String) async throws
    func songDownloadAction(for track: Track, downloads: DownloadStore) -> SongRowAction?
}

extension AppModule {
    var downloadsWholeAlbums: Bool { false }
    var libraryOrigin: LibraryOrigin { LibraryOrigin(rawValue: descriptor.id.rawValue, label: descriptor.title, systemImage: descriptor.systemImage) }
    var accountEntry: ModuleAccountEntry? { nil }
    func songAlbumRoute(for track: Track) -> AppRoute? { nil }
    func artistDestinations(for track: Track) async throws -> [PlayerArtistDestination] { [] }
    var artistNavigation: PlayerArtistNavigation { .perArtist }
    func openAccount() {}
    func dismissAccount() {}
    func deactivate() {}
    func install(in content: AnyView) -> AnyView { content }
    func handleURL(_ url: URL, host: ModuleHost) -> Bool { false }
    func searchSection(query: String) -> AnyView? { nil }
    func loginView() -> AnyView? { nil }
    func playlistPicker(for track: Track) -> AnyView? { nil }
    func collectionRoute(kind: String, itemID: String) -> AppRoute? { nil }
    func collectionRemoval(for item: MirroredCollection) -> LibraryRemoval? { nil }
    func removeCollection(kind: String, itemID: String) async throws { throw ModuleCapabilityError.unavailable }
    func songDownloadAction(for track: Track, downloads: DownloadStore) -> SongRowAction? { nil }

}

enum ModuleCapabilityError: LocalizedError {
    case unavailable
    var errorDescription: String? { "此来源的模块或操作当前不可用。" }
}

@Observable
final class ModuleRegistry {
    enum RegistrationError: Error { case empty, duplicateID(ModuleID) }
    private(set) var descriptors: [ModuleDescriptor]
    private var modules: [any AppModule]
    private var registrationRevision = 0

    init(_ modules: [any AppModule]) throws {
        guard !modules.isEmpty else { throw RegistrationError.empty }
        var seen = Set<ModuleID>()
        for module in modules {
            guard seen.insert(module.descriptor.id).inserted else {
                throw RegistrationError.duplicateID(module.descriptor.id)
            }
        }
        self.modules = modules
        descriptors = modules.map(\.descriptor)
    }

    func register(_ module: any AppModule) throws {
        guard self.module(for: module.descriptor.id) == nil else { throw RegistrationError.duplicateID(module.descriptor.id) }
        modules.append(module)
        registrationRevision += 1
        descriptors = modules.map(\.descriptor)
    }
    func remove(_ id: ModuleID) {
        registrationRevision += 1
        module(for: id)?.dismissAccount()
        module(for: id)?.deactivate()
        modules.removeAll { $0.descriptor.id == id }
        descriptors = modules.map(\.descriptor)
    }
    func contains(providerID: String) -> Bool { module(providerID: providerID) != nil }
    func loginView(providerID: String) -> AnyView? { module(providerID: providerID)?.loginView() }
    func requiresLogin(providerID: String) -> Bool {
        guard let entry = module(providerID: providerID)?.accountEntry else { return false }
        return !entry.isSignedIn && module(providerID: providerID)?.loginView() != nil
    }
    func playlistPicker(for track: Track) -> AnyView? {
        guard let source = track.remoteSource else { return nil }
        return module(providerID: source.providerID)?.playlistPicker(for: track)
    }
    func collectionRoute(providerID: String, kind: String, itemID: String) -> AppRoute? {
        module(providerID: providerID)?.collectionRoute(kind: kind, itemID: itemID)
    }
    func collectionRemoval(for item: MirroredCollection) -> LibraryRemoval? {
        module(providerID: item.providerID)?.collectionRemoval(for: item)
    }
    func removeCollection(providerID: String, kind: String, itemID: String) async throws {
        guard let module = module(providerID: providerID) else { throw ModuleCapabilityError.unavailable }
        try await module.removeCollection(kind: kind, itemID: itemID)
    }
    func songDownloadAction(for track: Track, downloads: DownloadStore) -> SongRowAction? {
        guard track.localSource == nil, let provider = track.playbackProviderID else { return nil }
        return module(providerID: provider)?.songDownloadAction(for: track, downloads: downloads)
    }
    func downloadsWholeAlbums(providerID: String) -> Bool { module(providerID: providerID)?.downloadsWholeAlbums ?? false }
    func origin(providerID: String) -> LibraryOrigin? {
        guard providerID != "local" else { return .local }
        return module(providerID: providerID)?.libraryOrigin
    }
    func songAlbumRoute(for track: Track) -> AppRoute? {
        guard let providerID = track.playbackProviderID else { return nil }
        return module(providerID: providerID)?.songAlbumRoute(for: track)
    }
    /// 本地音乐和没有对应来源的歌按作者分别进入。
    func artistNavigation(for track: Track) -> PlayerArtistNavigation {
        guard track.localSource == nil, let provider = track.playbackProviderID,
              let owner = module(providerID: provider) else { return .perArtist }
        return owner.artistNavigation
    }
    func artistDestinations(for track: Track) async throws -> [PlayerArtistDestination] {
        if track.localSource != nil {
            return LibraryArtistNames.split(track.artists).map {
                PlayerArtistDestination(name: $0, route: .libraryArtist($0, filter: .all))
            }
        }
        guard let provider = track.playbackProviderID, let owner = module(providerID: provider) else {
            throw ModuleCapabilityError.unavailable
        }
        let revision = registrationRevision
        let destinations = try await owner.artistDestinations(for: track)
        try Task.checkCancellation()
        guard revision == registrationRevision else { throw CancellationError() }
        return destinations
    }
    func descriptor(for id: ModuleID) -> ModuleDescriptor? { descriptors.first { $0.id == id } }
    /// 统一搜索的各组结果：按传入的搜索板块顺序显示；只包含 `ids` 里的模块。
    func searchSections(query: String, in ids: [ModuleID]) -> [(id: ModuleID, view: AnyView)] {
        ids.compactMap { id in module(for: id)?.searchSection(query: query).map { (id, $0) } }
    }
    func accountEntry(for id: ModuleID) -> ModuleAccountEntry? { module(for: id)?.accountEntry }
    func openAccount(for id: ModuleID) { module(for: id)?.openAccount() }
    func dismissAccounts() { modules.forEach { $0.dismissAccount() } }
    func rootView(for id: ModuleID) -> AnyView { module(for: id)?.rootView() ?? unavailable }
    func destination(for route: AppRoute) -> AnyView {
        module(for: route.moduleID)?.destination(for: route) ?? unavailable
    }
    func install(in content: AnyView) -> AnyView {
        modules.reversed().reduce(content) { $1.install(in: $0) }
    }
    @discardableResult
    func handleURL(_ url: URL, host: ModuleHost) -> Bool {
        modules.contains { $0.handleURL(url, host: host) }
    }
    private func module(providerID: String) -> (any AppModule)? { modules.first { $0.libraryOrigin.rawValue == providerID } }
    private func module(for id: ModuleID) -> (any AppModule)? { modules.first { $0.descriptor.id == id } }
    private var unavailable: AnyView {
        AnyView(ContentUnavailableView("模块不可用", systemImage: "square.stack.3d.up.slash", description: Text("此内容所属的模块尚未接入。")))
    }
}

/// Selection and stack state belong to the slot, never to an individual provider.
@Observable
final class ModuleHost {
    let settings: ModuleSettings
    var selection: ModuleID
    var paths: [ModuleID: [AppRoute]] = [:]
    var dismissPresentations = false

    init(settings: ModuleSettings) {
        self.settings = settings
        selection = settings.initialModule
    }
    func reconcileSelection() {
        // 「搜索」标签不是模块，不受模块显示设置影响。
        if selection != .search, !settings.isVisible(selection) { selection = settings.visibleModules[0] }
    }
    @discardableResult
    func select(_ id: ModuleID, path: [AppRoute] = []) -> Bool {
        guard settings.isVisible(id) else { return false }
        selection = id
        paths[id] = path
        dismissPresentations = true
        return true
    }
}
