import Foundation

/// A compiled-in platform owns its session and adapters. The host owns shared storage and playback.
@MainActor
struct PlatformRegistration {
    let descriptor: ModuleDescriptor
    var providerID: String? = nil
    var canDisable = true
    var migrateDownloads: ((Data) -> [DownloadJob]?)? = nil
    let make: (AppServices) -> PlatformRuntime
}

@MainActor
final class PlatformRuntime {
    let module: any AppModule
    let restore: () async -> Void
    let synchronize: (Bool) async -> Void
    let shutdown: () async -> Void

    init(module: any AppModule,
         restore: @escaping () async -> Void = {},
         synchronize: @escaping (Bool) async -> Void = { _ in },
         shutdown: @escaping () async -> Void = {}) {
        self.module = module
        self.restore = restore
        self.synchronize = synchronize
        self.shutdown = shutdown
    }
}
