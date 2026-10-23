import Foundation

/// The single assembly point that knows which providers ship in this application.
enum AppComposition {
    static var registrations: [PlatformRegistration] {
        [
         DizzyLabModule.registration,
         NeteaseModule.registration,
         QQMusicModule.registration,
         PlatformRegistration(descriptor: LocalLibraryModule.metadata, canDisable: false) {
             PlatformRuntime(module: LocalLibraryModule(library: $0.offlineLibrary))
         }]
    }
    static var descriptors: [ModuleDescriptor] { registrations.map(\.descriptor) }
    static func modules(services: AppServices) -> ModuleRegistry { services.modules }
    static func migrateDownloads(_ data: Data) -> [DownloadJob]? {
        registrations.lazy.compactMap { $0.migrateDownloads?(data) }.first
    }

    static func settings(modules: [ModuleDescriptor] = descriptors, defaults: UserDefaults = .standard) -> ModuleSettings {
        // Legacy navigation is an application migration, not part of the reusable slot.
        let legacy = TabSettings(defaults: defaults)
        func owner(_ tab: MainTab) -> ModuleID { tab == .localLibrary ? .localLibrary : ModuleID(rawValue: "dizzyLab") }
        let hidden = Set(modules.map(\.id).filter { id in
            let tabs = legacy.order.filter { owner($0) == id }
            return !tabs.isEmpty && tabs.allSatisfy { legacy.hidden.contains($0) }
        })
        return ModuleSettings(modules: modules, defaults: defaults,
                              legacy: ModulePreferences(order: legacy.order.map(owner), hidden: hidden, startup: owner(legacy.startupTab)))
    }
}
