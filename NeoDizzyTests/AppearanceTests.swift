import Foundation
import Testing
@testable import NeoDizzy

struct AppearanceTests {
    private func makeDefaults() -> UserDefaults {
        let name = "AppearanceTests-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: name)!
        defaults.removePersistentDomain(forName: name)
        return defaults
    }

    @Test func defaultsToSystemAppearanceAndNeutralAccent() {
        let settings = AppearanceSettings(defaults: makeDefaults())
        #expect(settings.mode == .system)
        #expect(settings.accent == .neutral)
    }

    @Test func choicesPersistAcrossLaunches() {
        let defaults = makeDefaults()
        let settings = AppearanceSettings(defaults: defaults)
        settings.mode = .light
        let restored = AppearanceSettings(defaults: defaults)
        #expect(restored.mode == .light)
    }

    /// 改坏的存档回到跟随系统。
    @Test func unknownStoredModeFallsBackToSystem() {
        let defaults = makeDefaults()
        defaults.set("sepia", forKey: AppearanceSettings.modeKey)
        let settings = AppearanceSettings(defaults: defaults)
        #expect(settings.mode == .system)
    }

    /// 没有登记品牌色的模块用中性色。
    @Test func descriptorDefaultsToNeutralAccent() {
        let descriptor = ModuleDescriptor(id: ModuleID(rawValue: "fixture"), title: "Fixture", systemImage: "square")
        #expect(descriptor.accent == .neutral)
    }
}
