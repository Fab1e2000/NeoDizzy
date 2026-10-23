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

    @Test func defaultsToSystemAppearanceAndGoldTheme() {
        let settings = AppearanceSettings(defaults: makeDefaults())
        #expect(settings.mode == .system)
        #expect(settings.themeID == AppTheme.defaultID)
    }

    @Test func choicesPersistAcrossLaunches() {
        let defaults = makeDefaults()
        let settings = AppearanceSettings(defaults: defaults)
        settings.mode = .light
        settings.themeID = "teal"
        let restored = AppearanceSettings(defaults: defaults)
        #expect(restored.mode == .light)
        #expect(restored.theme.id == "teal")
    }

    /// 删掉的主题或改坏的存档回到默认主题。
    @Test func unknownStoredThemeFallsBackToDefault() {
        let defaults = makeDefaults()
        defaults.set("removed", forKey: AppearanceSettings.themeKey)
        defaults.set("sepia", forKey: AppearanceSettings.modeKey)
        let settings = AppearanceSettings(defaults: defaults)
        #expect(settings.themeID == AppTheme.defaultID)
        #expect(settings.mode == .system)
    }
}
