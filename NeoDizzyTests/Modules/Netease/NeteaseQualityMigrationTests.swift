import Foundation
import Testing
@testable import NeoDizzy

@MainActor struct NeteaseQualityMigrationTests {
    @Test func unifiedQualityMigratesAndPersists() throws {
        let name = "NeteaseQuality.\(UUID())"
        let defaults = try #require(UserDefaults(suiteName: name))
        defer { defaults.removePersistentDomain(forName: name) }
        defaults.set("hires", forKey: "netease.quality.wifi")
        defaults.set("standard", forKey: "netease.quality.download")
        let settings = NeteasePlaybackSettings(defaults: defaults)
        #expect(settings.quality == .hiResolution)
        var changes = 0
        settings.changed = { changes += 1 }
        settings.quality = .master
        settings.quality = .master
        #expect(changes == 1)
        #expect(settings.selected == .master)
        #expect(NeteasePlaybackSettings(defaults: defaults).quality == .master)
    }
}
