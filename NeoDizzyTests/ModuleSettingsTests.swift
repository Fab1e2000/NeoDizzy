import Foundation
import Testing
@testable import NeoDizzy

struct ModuleSettingsTests {
    private func defaults() throws -> UserDefaults {
        try #require(UserDefaults(suiteName: "ModuleSettingsTests.\(UUID())"))
    }

    private func clear(_ store: UserDefaults) {
        for key in ["mainModules.v1", "search.moduleOrder.v1", "mainTabs.v1", "mainTabs.startup"] { store.removeObject(forKey: key) }
    }

    @Test func mergesLegacyPagesWithoutHidingAnEnabledSource() throws {
        let store = try defaults()
        defer { clear(store) }
        store.set(Data(#"{"order":["localLibrary","feed","discover","labels","purchased","shuffle"],"hidden":["discover","labels","shuffle"]}"#.utf8), forKey: "mainTabs.v1")
        store.set("purchased", forKey: "mainTabs.startup")
        let modules = AppComposition.settings(modules: [DizzyLabModule.metadata, LocalLibraryModule.metadata], defaults: store)
        #expect(modules.order == [.localLibrary, .dizzyLab])
        #expect(modules.visibleModules == [.localLibrary, .dizzyLab])
        #expect(modules.startupModule == .dizzyLab)
        #expect(modules.initialModule == .dizzyLab)
        // 旧页面设置仍可被 macOS 读取。
        #expect(TabSettings(defaults: store).hidden == [.discover, .labels, .shuffle])
    }

    @Test func keepsDizzyLabDisabledOnlyWhenAllItsLegacyPagesWereHidden() throws {
        let store = try defaults()
        defer { clear(store) }
        let legacy = TabSettings(defaults: store)
        for tab in MainTab.primary where tab != .localLibrary { legacy.setVisible(false, for: tab) }
        legacy.startupTab = .shuffle
        let modules = AppComposition.settings(modules: [DizzyLabModule.metadata, LocalLibraryModule.metadata], defaults: store)
        #expect(modules.visibleModules == [.localLibrary])
        #expect(modules.startupModule == .dizzyLab)
        #expect(modules.initialModule == .localLibrary)
        modules.setVisible(true, for: .dizzyLab)
        #expect(modules.initialModule == .dizzyLab)
    }

    @Test func migrationRunsOnceAndDoesNotOverwriteModulePreferences() throws {
        let store = try defaults()
        defer { clear(store) }
        let modules = AppComposition.settings(modules: [DizzyLabModule.metadata, LocalLibraryModule.metadata], defaults: store)
        modules.reorder([.localLibrary, .dizzyLab])
        modules.startupModule = .localLibrary
        modules.setVisible(false, for: .dizzyLab)
        TabSettings(defaults: store).reset()
        let restored = AppComposition.settings(modules: [DizzyLabModule.metadata, LocalLibraryModule.metadata], defaults: store)
        #expect(restored.order == [.localLibrary, .dizzyLab])
        #expect(restored.visibleModules == [.localLibrary])
        #expect(restored.initialModule == .localLibrary)
        restored.setVisible(false, for: .localLibrary)
        #expect(restored.visibleModules == [.localLibrary])
        restored.reset()
        #expect(restored.visibleModules == [ModuleID.dizzyLab, .localLibrary])
    }

    @Test func repairsUnknownDuplicateAndAllHiddenSavedModules() throws {
        let store = try defaults()
        defer { clear(store) }
        store.set(Data(#"{"order":["unknown","localLibrary","localLibrary"],"hidden":["dizzyLab","localLibrary"],"startup":"removed"}"#.utf8), forKey: "mainModules.v1")
        let modules = AppComposition.settings(modules: [DizzyLabModule.metadata, LocalLibraryModule.metadata], defaults: store)
        #expect(modules.order == [.localLibrary, .dizzyLab])
        #expect(modules.visibleModules == [.localLibrary])
        #expect(modules.initialModule == .localLibrary)
        modules.reorder([.dizzyLab, .dizzyLab])
        #expect(modules.order == [.localLibrary, .dizzyLab])
    }

    @Test func corruptSnapshotFallsBackToLegacyStartup() throws {
        let store = try defaults()
        defer { clear(store) }
        store.set(Data("invalid json".utf8), forKey: "mainModules.v1")
        store.set("localLibrary", forKey: "mainTabs.startup")
        let modules = AppComposition.settings(modules: [DizzyLabModule.metadata, LocalLibraryModule.metadata], defaults: store)
        #expect(modules.visibleModules == [.dizzyLab, .localLibrary])
        #expect(modules.initialModule == .localLibrary)
    }
    @Test func newlyInstalledNeteaseIsVisibleWithoutChangingSavedStartup() throws {
        let store = try defaults()
        defer { clear(store) }
        store.set(Data(#"{"order":["localLibrary","dizzyLab"],"hidden":["dizzyLab"],"startup":"localLibrary"}"#.utf8), forKey: "mainModules.v1")
        let modules = AppComposition.settings(defaults: store)
        #expect(modules.order == [.localLibrary, .dizzyLab, .netease])
        #expect(modules.visibleModules == [.localLibrary, .netease])
        #expect(modules.initialModule == .localLibrary)
    }
    @Test func legacyMigrationDoesNotTreatNewProviderAsHidden() throws {
        let store = try defaults()
        defer { clear(store) }
        let modules = AppComposition.settings(defaults: store)
        #expect(modules.visibleModules.contains(.netease))
    }
    @Test func searchOrderPersistsIndependentlyAndRetainsHiddenPositions() throws {
        let store = try defaults()
        defer { clear(store) }
        let settings = AppComposition.settings(defaults: store)
        let originalModules = settings.order
        settings.reorderSearch([.netease, .dizzyLab, .localLibrary])
        settings.setVisible(false, for: .dizzyLab)
        let restored = AppComposition.settings(defaults: store)
        #expect(restored.order == originalModules)
        #expect(restored.visibleSearchModules == [.netease, .localLibrary])
        restored.setVisible(true, for: .dizzyLab)
        #expect(restored.visibleSearchModules == [.netease, .dizzyLab, .localLibrary])
        restored.reorderSearch([.netease, .netease, .localLibrary])
        #expect(restored.searchOrder == [.netease, .dizzyLab, .localLibrary])
        restored.resetSearchOrder()
        #expect(restored.searchOrder.first == .localLibrary)
    }

    @Test func searchOrderRepairsUnknownAndDuplicateIDs() throws {
        let store = try defaults()
        defer { clear(store) }
        store.set(["removed", "netease", "netease"], forKey: "search.moduleOrder.v1")
        let settings = AppComposition.settings(defaults: store)
        #expect(settings.searchOrder.first == .netease)
        #expect(Set(settings.searchOrder) == Set(settings.order))
        #expect(settings.searchOrder.count == settings.order.count)
    }

}
