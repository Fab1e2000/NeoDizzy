import Foundation
import Testing
@testable import NeoDizzy

struct ModuleSettingsTests {
    // These values are fixtures for persisted namespaces, not platform implementations.
    private let oldSource = ModuleID(rawValue: "dizzyLab")
    private let newSource = ModuleID(rawValue: "netease")
    private let anotherSource = ModuleID(rawValue: "qqmusic")
    private var oldDescriptors: [ModuleDescriptor] { descriptors([oldSource, .localLibrary]) }
    private var allDescriptors: [ModuleDescriptor] { descriptors([oldSource, newSource, anotherSource, .localLibrary]) }
    private func descriptors(_ ids: [ModuleID]) -> [ModuleDescriptor] {
        ids.map { .init(id: $0, title: $0.rawValue, systemImage: "music.note") }
    }
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
        let modules = AppComposition.settings(modules: oldDescriptors, defaults: store)
        #expect(modules.order == [.localLibrary, oldSource])
        #expect(modules.visibleModules == [.localLibrary, oldSource])
        #expect(modules.startupModule == oldSource)
        #expect(modules.initialModule == oldSource)
        // 旧页面设置仍可被 macOS 读取。
        #expect(TabSettings(defaults: store).hidden == [.discover, .labels, .shuffle])
    }

    @Test func keepsDizzyLabDisabledOnlyWhenAllItsLegacyPagesWereHidden() throws {
        let store = try defaults()
        defer { clear(store) }
        let legacy = TabSettings(defaults: store)
        for tab in MainTab.primary where tab != .localLibrary { legacy.setVisible(false, for: tab) }
        legacy.startupTab = .shuffle
        let modules = AppComposition.settings(modules: oldDescriptors, defaults: store)
        #expect(modules.visibleModules == [.localLibrary])
        #expect(modules.startupModule == oldSource)
        #expect(modules.initialModule == .localLibrary)
        modules.setVisible(true, for: oldSource)
        #expect(modules.initialModule == oldSource)
    }

    @Test func migrationRunsOnceAndDoesNotOverwriteModulePreferences() throws {
        let store = try defaults()
        defer { clear(store) }
        let modules = AppComposition.settings(modules: oldDescriptors, defaults: store)
        modules.reorder([.localLibrary, oldSource])
        modules.startupModule = .localLibrary
        modules.setVisible(false, for: oldSource)
        TabSettings(defaults: store).reset()
        let restored = AppComposition.settings(modules: oldDescriptors, defaults: store)
        #expect(restored.order == [.localLibrary, oldSource])
        #expect(restored.visibleModules == [.localLibrary])
        #expect(restored.initialModule == .localLibrary)
        restored.setVisible(false, for: .localLibrary)
        #expect(restored.visibleModules == [.localLibrary])
        restored.reset()
        #expect(restored.visibleModules == [oldSource, .localLibrary])
    }

    @Test func repairsUnknownDuplicateAndAllHiddenSavedModules() throws {
        let store = try defaults()
        defer { clear(store) }
        store.set(Data(#"{"order":["unknown","localLibrary","localLibrary"],"hidden":["dizzyLab","localLibrary"],"startup":"removed"}"#.utf8), forKey: "mainModules.v1")
        let modules = AppComposition.settings(modules: oldDescriptors, defaults: store)
        #expect(modules.order == [.localLibrary, oldSource])
        #expect(modules.visibleModules == [.localLibrary])
        #expect(modules.initialModule == .localLibrary)
        modules.reorder([oldSource, oldSource])
        #expect(modules.order == [.localLibrary, oldSource])
    }

    @Test func corruptSnapshotFallsBackToLegacyStartup() throws {
        let store = try defaults()
        defer { clear(store) }
        store.set(Data("invalid json".utf8), forKey: "mainModules.v1")
        store.set("localLibrary", forKey: "mainTabs.startup")
        let modules = AppComposition.settings(modules: oldDescriptors, defaults: store)
        #expect(modules.visibleModules == [oldSource, .localLibrary])
        #expect(modules.initialModule == .localLibrary)
    }
    @Test func newlyInstalledNeteaseIsVisibleWithoutChangingSavedStartup() throws {
        let store = try defaults()
        defer { clear(store) }
        store.set(Data(#"{"order":["localLibrary","dizzyLab"],"hidden":["dizzyLab"],"startup":"localLibrary"}"#.utf8), forKey: "mainModules.v1")
        let modules = AppComposition.settings(modules: allDescriptors, defaults: store)
        #expect(modules.order == [.localLibrary, oldSource, newSource, anotherSource])
        #expect(modules.visibleModules == [.localLibrary, newSource, anotherSource])
        #expect(modules.initialModule == .localLibrary)
    }
    @Test func legacyMigrationDoesNotTreatNewProviderAsHidden() throws {
        let store = try defaults()
        defer { clear(store) }
        let modules = AppComposition.settings(modules: allDescriptors, defaults: store)
        #expect(modules.visibleModules.contains(newSource))
    }
    @Test func searchOrderPersistsIndependentlyAndRetainsHiddenPositions() throws {
        let store = try defaults()
        defer { clear(store) }
        let settings = AppComposition.settings(modules: allDescriptors, defaults: store)
        let originalModules = settings.order
        settings.reorderSearch([newSource, oldSource, .localLibrary, anotherSource])
        settings.setVisible(false, for: oldSource)
        let restored = AppComposition.settings(modules: allDescriptors, defaults: store)
        #expect(restored.order == originalModules)
        #expect(restored.visibleSearchModules == [newSource, .localLibrary, anotherSource])
        restored.setVisible(true, for: oldSource)
        #expect(restored.visibleSearchModules == [newSource, oldSource, .localLibrary, anotherSource])
        restored.reorderSearch([newSource, newSource, .localLibrary, anotherSource])
        #expect(restored.searchOrder == [newSource, oldSource, .localLibrary, anotherSource])
        restored.resetSearchOrder()
        #expect(restored.searchOrder.first == .localLibrary)
    }

    @Test func searchOrderRepairsUnknownAndDuplicateIDs() throws {
        let store = try defaults()
        defer { clear(store) }
        store.set(["removed", "netease", "netease"], forKey: "search.moduleOrder.v1")
        let settings = AppComposition.settings(modules: allDescriptors, defaults: store)
        #expect(settings.searchOrder.first == newSource)
        #expect(Set(settings.searchOrder) == Set(settings.order))
        #expect(settings.searchOrder.count == settings.order.count)
    }

}
