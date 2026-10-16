import SwiftUI

struct ModuleDescriptor: Identifiable, Equatable {
    let id: ModuleID
    let title: String
    let systemImage: String
}

/// Optional account capability; modules with accounts get a row in the global settings.
struct ModuleAccountEntry {
    let title: String
    let avatarURL: URL?
    var isSignedIn = false
}

/// A compiled-in feature plugs into these slots; the host never switches on provider IDs.
@MainActor
protocol AppModule {
    var descriptor: ModuleDescriptor { get }
    var accountEntry: ModuleAccountEntry? { get }
    func openAccount()
    func dismissAccount()
    func rootView() -> AnyView
    func destination(for route: AppRoute) -> AnyView?
    func install(in content: AnyView) -> AnyView
    func songActions(for track: Track, onImportLyrics: (() -> Void)?) -> AnyView?
    func handleURL(_ url: URL, host: ModuleHost) -> Bool
    /// 统一搜索里这个模块的一组结果（含标题和「查看全部」）；没有搜索能力的模块返回 nil。
    func searchSection(query: String) -> AnyView?
}

extension AppModule {
    var accountEntry: ModuleAccountEntry? { nil }
    func songActions(for track: Track, onImportLyrics: (() -> Void)?) -> AnyView? { nil }
    func openAccount() {}
    func dismissAccount() {}
    func install(in content: AnyView) -> AnyView { content }
    func handleURL(_ url: URL, host: ModuleHost) -> Bool { false }
    func searchSection(query: String) -> AnyView? { nil }
}

@Observable
final class ModuleRegistry {
    enum RegistrationError: Error { case empty, duplicateID(ModuleID) }
    let descriptors: [ModuleDescriptor]
    @ObservationIgnored private let modules: [any AppModule]

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

    func songActions(for track: Track, onImportLyrics: (() -> Void)?) -> AnyView? {
        modules.lazy.compactMap { $0.songActions(for: track, onImportLyrics: onImportLyrics) }.first
    }
    func descriptor(for id: ModuleID) -> ModuleDescriptor? { descriptors.first { $0.id == id } }
    /// 统一搜索的各组结果：资料库在最前，其余按模块顺序；只包含 `ids` 里的模块。
    func searchSections(query: String, in ids: [ModuleID]) -> [(id: ModuleID, view: AnyView)] {
        Self.searchOrder(ids).compactMap { id in module(for: id)?.searchSection(query: query).map { (id, $0) } }
    }
    static func searchOrder(_ ids: [ModuleID]) -> [ModuleID] {
        ids.filter { $0 == .localLibrary } + ids.filter { $0 != .localLibrary }
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
