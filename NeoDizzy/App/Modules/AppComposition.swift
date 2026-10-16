import Foundation

/// The single assembly point that knows which providers ship in this application.
enum AppComposition {
    static var descriptors: [ModuleDescriptor] { [DizzyLabModule.metadata, NeteaseModule.metadata, LocalLibraryModule.metadata] }

    static func modules(services: AppServices) -> ModuleRegistry {
        do {
            return try ModuleRegistry([
                DizzyLabModule(services: services.dizzyLab),
                NeteaseModule(store: services.netease),
                LocalLibraryModule(library: services.offlineLibrary)
            ])
        } catch { preconditionFailure("Invalid module registration: \(error)") }
    }

    static func settings(modules: [ModuleDescriptor] = descriptors, defaults: UserDefaults = .standard) -> ModuleSettings {
        // Legacy navigation is an application migration, not part of the reusable slot.
        let legacy = TabSettings(defaults: defaults)
        func owner(_ tab: MainTab) -> ModuleID { tab == .localLibrary ? .localLibrary : .dizzyLab }
        let hidden = Set(descriptors.map(\.id).filter { id in
            let tabs = legacy.order.filter { owner($0) == id }
            return !tabs.isEmpty && tabs.allSatisfy { legacy.hidden.contains($0) }
        })
        return ModuleSettings(modules: modules, defaults: defaults,
                              legacy: ModulePreferences(order: legacy.order.map(owner), hidden: hidden, startup: owner(legacy.startupTab)))
    }
}
