import Foundation

extension DizzyLabModule {
    static var registration: PlatformRegistration {
        PlatformRegistration(descriptor: metadata, providerID: "dizzylab", migrateDownloads: DizzyLabDownloadProvider.migrate) { services in
            let platform = DizzyLabServices(library: services.offlineLibrary, downloads: services.downloads)
            services.downloads.register(DizzyLabDownloadProvider(library: services.offlineLibrary))
            try? FileManager.default.createDirectory(at: URL.documentsDirectory.appending(path: "dizzylab", directoryHint: .isDirectory),
                                                     withIntermediateDirectories: true)
            services.favorites.migrateSavedSongs(from: services.savedLibrary)
            services.favorites.registerDeviceProvider("dizzylab")
            services.resolver.register("dizzylab", provider: DizzyLabPlaybackProvider().provider)
            services.player.registerDiscoverySelection("dizzylab") { try await DizzyCommunity.shared.shuffle() }
            services.playbackHistory.register("dizzylab") { $0.discID.isEmpty ? nil : $0.discID }
            services.accountLibrary.registerDizzyLab { [weak platform] in platform?.account.account?.userID }
            services.libraryProviders.registerDizzyLab()
            let observers = DizzyLabRuntimeObservers(player: services.player)
            let module = DizzyLabModule(services: platform, onAccountChange: { [weak services] in
                guard let services, services.isEnabled(.dizzyLab) else { return }
                Task { await services.syncAccountLibrary(force: true) }
            }, onLibraryChange: { [weak services] in
                guard let services, services.isEnabled(.dizzyLab) else { return }
                Task { await services.syncAccountLibrary(force: true) }
            })
            return PlatformRuntime(module: module, restore: {
                await DizzyHTTPClient.shared.setEnabled(true)
            }, shutdown: {
                observers.stop()
                platform.purchases.deactivate()
                await platform.account.suspend()
                await DizzyHTTPClient.shared.setEnabled(false)
            })
        }
    }
}

private final class DizzyLabRuntimeObservers {
    private var tokens: [NSObjectProtocol] = []
    init(player: PlayerStore) {
        tokens.append(NotificationCenter.default.addObserver(forName: .dizzyAccountDidChange, object: nil, queue: .main) { [weak player] _ in
            MainActor.assumeIsolated { player?.remoteAccountDidChange(providerID: "dizzylab") }
        })
        tokens.append(NotificationCenter.default.addObserver(forName: .dizzyPurchaseDidComplete, object: nil, queue: .main) { [weak player] notification in
            guard let discID = notification.object as? String else { return }
            MainActor.assumeIsolated { player?.sourceContentDidChange(providerID: "dizzylab", collectionID: discID) }
        })
    }
    func stop() {
        tokens.forEach(NotificationCenter.default.removeObserver)
        tokens.removeAll()
    }
    deinit { tokens.forEach(NotificationCenter.default.removeObserver) }
}
