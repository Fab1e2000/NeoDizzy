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

    @Test func defaultsToLightAppearanceAndNeutralAccent() {
        let settings = AppearanceSettings(defaults: makeDefaults())
        #expect(settings.mode == .light)
        #expect(settings.accent == .neutral)
    }

    @Test func choicesPersistAcrossLaunches() {
        let defaults = makeDefaults()
        let settings = AppearanceSettings(defaults: defaults)
        settings.mode = .light
        let restored = AppearanceSettings(defaults: defaults)
        #expect(restored.mode == .light)
    }

    /// 改坏的存档统一回到浅色。
    @Test func unknownStoredModeFallsBackToLight() {
        let defaults = makeDefaults()
        defaults.set("sepia", forKey: AppearanceSettings.modeKey)
        let settings = AppearanceSettings(defaults: defaults)
        #expect(settings.mode == .light)
    }

    @Test(arguments: [AppAppearance.dark, .system])
    func legacyAndRestoredModesCannotEnableDarkAppearance(mode: AppAppearance) {
        let defaults = makeDefaults()
        defaults.set(mode.rawValue, forKey: AppearanceSettings.modeKey)
        let settings = AppearanceSettings(defaults: defaults)
        #expect(settings.mode == .light)
        settings.mode = mode
        #expect(settings.mode == .light)
        #expect(defaults.string(forKey: AppearanceSettings.modeKey) == "light")
    }

    /// 没有登记品牌色的模块用中性色。
    @Test func descriptorDefaultsToNeutralAccent() {
        let descriptor = ModuleDescriptor(id: ModuleID(rawValue: "fixture"), title: "Fixture", systemImage: "square")
        #expect(descriptor.accent == .neutral)
    }
}
