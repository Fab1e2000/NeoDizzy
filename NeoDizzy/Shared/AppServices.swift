#if os(iOS)
import Foundation
import Observation

/// Shared resources survive individual platform lifetimes, including background downloads.
@Observable @MainActor
final class AppServices {
    let offlineLibrary: OfflineLibraryStore
    let downloads: DownloadStore
    let player: PlayerStore
    let resolver: StreamResolver
    let savedLibrary: SavedLibraryStore
    let favorites: FavoritesStore
    let accountLibrary: AccountLibraryMirror
    let playbackHistory: PlaybackHistoryStore
    let libraryProviders = LibraryProviderRegistry()
    let registrations: [PlatformRegistration]
    private(set) var transitioning = Set<ModuleID>()
    private(set) var enabled: Set<ModuleID> = []
    @ObservationIgnored private var runtimes: [ModuleID: PlatformRuntime] = [:]
    @ObservationIgnored private let defaults: UserDefaults
    @ObservationIgnored private var restored = false
    private static let disabledKey = "moduleServices.disabled.v1"

    @ObservationIgnored lazy var modules: ModuleRegistry = {
        do { return try ModuleRegistry(registrations.compactMap { runtimes[$0.descriptor.id]?.module }) }
        catch { preconditionFailure("Invalid module configuration: \(error)") }
    }()
    @ObservationIgnored lazy var moduleSettings = AppComposition.settings(modules: modules.descriptors, defaults: defaults)

    init(registrations suppliedRegistrations: [PlatformRegistration]? = nil,
         defaults: UserDefaults = .standard, library: OfflineLibraryStore? = nil,
         storageDirectory: URL? = nil,
         migrateDownloads: ((Data) -> [DownloadJob]?)? = nil) {
        let registrations = suppliedRegistrations ?? AppComposition.registrations
        precondition(!registrations.isEmpty && registrations.contains { !$0.canDisable })
        precondition(Set(registrations.map { $0.descriptor.id }).count == registrations.count)
        precondition(Set(registrations.map { $0.providerID ?? $0.descriptor.id.rawValue }).count == registrations.count)
        self.registrations = registrations
        self.defaults = defaults
        let dataDirectory = storageDirectory ?? URL.applicationSupportDirectory
        savedLibrary = SavedLibraryStore(directory: dataDirectory.appendingPathComponent("Library"))
        favorites = FavoritesStore(directory: dataDirectory.appendingPathComponent("Library"))
        accountLibrary = AccountLibraryMirror(directory: dataDirectory.appendingPathComponent("Library"))
        playbackHistory = PlaybackHistoryStore(defaults: defaults)
        let library = library ?? OfflineLibraryStore(libraryRoot: .documentsDirectory)
        offlineLibrary = library
        downloads = DownloadStore(library: library, directory: dataDirectory.appendingPathComponent("Downloads"),
                                  transportIdentifier: storageDirectory == nil ? BackgroundDownloadBridge.identifier : "module-tests.\(UUID())",
                                  defaults: defaults, migrateLegacy: migrateDownloads ?? { AppComposition.migrateDownloads($0) })
        resolver = StreamResolver(qualityLocalFile: { [weak library] track, quality in
            library?.localFile(for: track, quality: quality)
        }, qualityLocalAccess: { [weak library] track, quality in
            library?.access(for: track, quality: quality)
        })
        player = PlayerStore(resolver: resolver, persistence: PlaybackPersistence(defaults: defaults))
        let history = playbackHistory
        player.reporting.onStart = { [weak history] track, _ in history?.record(track) }
        favorites.setDeviceProviders(["local"])
        let disabled = Set(defaults.stringArray(forKey: Self.disabledKey) ?? [])
        for registration in registrations where !registration.canDisable || !disabled.contains(registration.descriptor.id.rawValue) {
            let id = registration.descriptor.id
            enabled.insert(id)
            runtimes[id] = registration.make(self)
        }
    }

    func isEnabled(_ id: ModuleID) -> Bool { enabled.contains(id) }

    /// Hiding is only navigation. Disabling revokes capabilities before awaiting cleanup.
    func setEnabled(_ value: Bool, for id: ModuleID) async {
        guard let registration = registrations.first(where: { $0.descriptor.id == id }),
              registration.canDisable, value != enabled.contains(id), !transitioning.contains(id) else { return }
        transitioning.insert(id)
        defer { transitioning.remove(id) }
        // Materialize registries before changing the runtime list.
        let registry = modules, settings = moduleSettings
        if value {
            enabled.insert(id)
            saveEnabled()
            let runtime = registration.make(self)
            runtimes[id] = runtime
            do { try registry.register(runtime.module) }
            catch { preconditionFailure("Duplicate module registration: \(error)") }
            settings.updateInstalled(registry.descriptors)
            await runtime.restore()
            await syncAccountLibrary(force: true)
        } else {
            enabled.remove(id)
            saveEnabled()
            let runtime = runtimes.removeValue(forKey: id)
            registry.remove(id)
            settings.updateInstalled(registry.descriptors)
            let providerID = registration.providerID ?? id.rawValue
            favorites.unregister(providerID)
            accountLibrary.unregister(providerID)
            libraryProviders.unregister(providerID)
            playbackHistory.unregister(providerID)
            await player.disableProvider(providerID: providerID)
            async let downloadsStopped: Void = downloads.unregister(providerID)
            async let runtimeStopped: Void = runtime?.shutdown() ?? ()
            _ = await (downloadsStopped, runtimeStopped)
        }
    }

    private func saveEnabled() {
        defaults.set(registrations.filter { $0.canDisable && !enabled.contains($0.descriptor.id) }.map { $0.descriptor.id.rawValue },
                     forKey: Self.disabledKey)
    }

    func syncAccountLibrary(force: Bool) async {
        async let mirrorDone: Void = accountLibrary.refresh(force: force)
        async let favoritesDone: Void = favorites.refresh()
        let work = registrations.compactMap { registration -> Task<Void, Never>? in
            guard let runtime = runtimes[registration.descriptor.id] else { return nil }
            return Task { await runtime.synchronize(force) }
        }
        for task in work { await task.value }
        _ = await (mirrorDone, favoritesDone)
    }

    func restore() async {
        guard !restored else { return }
        restored = true
        await offlineLibrary.restore()
        await downloads.restore()
        for registration in registrations { await runtimes[registration.descriptor.id]?.restore() }
        player.restore()
    }
}
#endif
