import SwiftUI

struct ModuleDescriptor: Identifiable, Equatable {
    let id: ModuleID
    let title: String
    let systemImage: String
}

/// Optional account capability; modules without accounts contribute no avatar button.
struct ModuleAccountEntry {
    let title: String
    let avatarURL: URL?
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
}

extension AppModule {
    var accountEntry: ModuleAccountEntry? { nil }
    func songActions(for track: Track, onImportLyrics: (() -> Void)?) -> AnyView? { nil }
    func openAccount() {}
    func dismissAccount() {}
    func install(in content: AnyView) -> AnyView { content }
    func handleURL(_ url: URL, host: ModuleHost) -> Bool { false }
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
        if !settings.isVisible(selection) { selection = settings.visibleModules[0] }
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
