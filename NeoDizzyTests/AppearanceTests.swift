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
        #expect(settings.theme.iconName == "NeoDizzyIcon")
    }

    @Test func choicesPersistAcrossLaunches() {
        let defaults = makeDefaults()
        let settings = AppearanceSettings(defaults: defaults)
        settings.mode = .light
        settings.themeID = "teal"
        let restored = AppearanceSettings(defaults: defaults)
        #expect(restored.mode == .light)
        #expect(restored.theme.id == "teal")
        #expect(restored.theme.iconName == "NeoDizzyIcon-teal")
    }

    @Test func albumDimmingDefaultsPersistsAndClamps() {
        let defaults = makeDefaults()
        let settings = AppearanceSettings(defaults: defaults)
        #expect(settings.albumDimming == AppearanceSettings.defaultAlbumDimming)
        settings.albumDimming = 40
        #expect(AppearanceSettings(defaults: defaults).albumDimming == 40)
        settings.albumDimming = 150
        #expect(settings.albumDimming == 100)
        #expect(AppearanceSettings(defaults: defaults).albumDimming == 100)
        settings.albumDimming = -3
        #expect(settings.albumDimming == 0)
        defaults.set(999, forKey: AppearanceSettings.albumDimmingKey)
        #expect(AppearanceSettings(defaults: defaults).albumDimming == 100)
    }

    /// 删掉的主题或改坏的存档回到默认主题，不会指向不存在的图标。
    @Test func unknownStoredThemeFallsBackToDefault() {
        let defaults = makeDefaults()
        defaults.set("removed", forKey: AppearanceSettings.themeKey)
        defaults.set("sepia", forKey: AppearanceSettings.modeKey)
        let settings = AppearanceSettings(defaults: defaults)
        #expect(settings.themeID == AppTheme.defaultID)
        #expect(settings.mode == .system)
    }

    /// 每个主题都要有生成好的图标，并登记为 iOS 备选图标；增删主题后需要重新运行生成脚本。
    @Test func everyThemeHasRegisteredIcon() throws {
        let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
        let project = try String(contentsOf: root.appending(path: "project.yml"), encoding: .utf8)
        let line = try #require(project.split(separator: "\n").first { $0.contains("ASSETCATALOG_COMPILER_ALTERNATE_APPICON_NAMES") })
        let registered = Set(line.split(separator: "\"")[1].split(separator: " ").map(String.init))
        let alternates = Set(AppTheme.presets.filter { $0.id != AppTheme.defaultID }.map(\.iconName))
        #expect(registered == alternates)
        for theme in AppTheme.presets {
            let icon = root.appending(path: "NeoDizzy/Resources/AppIcons/\(theme.iconName).icon/icon.json")
            #expect(FileManager.default.fileExists(atPath: icon.path), "缺少 \(theme.iconName)")
            let dock = root.appending(path: "NeoDizzyMac/Resources/DockIcons.xcassets/DockIcon-\(theme.id)-dark.imageset")
            #expect(FileManager.default.fileExists(atPath: dock.path), "缺少 \(theme.id) 的 Dock 图标")
        }
    }
}
