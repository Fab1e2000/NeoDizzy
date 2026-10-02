import Foundation
import Testing
@testable import NeoDizzy

struct NavigationModelTests {
    @Test func allTabsArePrimaryAndSearchIsNotATab() {
        #expect(Set(MainTab.primary) == Set(MainTab.allCases))
        #expect(MainTab(rawValue: "search") == nil)
    }

    @Test func everyTabHasItsOwnIcon() {
        let icons = MainTab.allCases.map(\.systemImage)
        #expect(Set(icons).count == icons.count)
    }

    @Test func routeTitlesUseSiteNames() {
        #expect(AppRoute.label(name: "Kirisense雾见").title == "Kirisense雾见")
        #expect(AppRoute.tag("电子").title == "#电子")
    }
}

struct TabSettingsTests {
    @Test func legacySearchPreferencesAreDiscardedWithoutLosingOtherTabs() throws {
        let suite = "LegacySearchTabTests.\(UUID())"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        defaults.set("search", forKey: "mainTabs.startup")
        defaults.set(Data(#"{"order":["localLibrary","search","discover","labels","feed","purchased"],"hidden":["search","feed"]}"#.utf8), forKey: "mainTabs.v1")
        let settings = TabSettings(defaults: defaults)
        #expect(settings.initialTab == .discover)
        #expect(settings.order.first == .localLibrary)
        #expect(settings.hidden == [.feed])
        #expect(settings.order == [.localLibrary, .discover, .shuffle, .labels, .feed, .purchased])
        #expect(settings.isVisible(.shuffle))
        #expect(settings.visibleTabs.count == 5)
    }

    @Test func shuffleTabCanBeStartupAndHiddenWithoutLosingPreferences() throws {
        let suite = "ShuffleTabTests.\(UUID())"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let settings = TabSettings(defaults: defaults)
        settings.startupTab = .shuffle
        #expect(TabSettings(defaults: defaults).initialTab == .shuffle)
        settings.setVisible(false, for: .shuffle)
        let restored = TabSettings(defaults: defaults)
        #expect(restored.startupTab == .shuffle)
        #expect(restored.initialTab == .discover)
        #expect(!restored.isVisible(.shuffle))
    }

    @Test func startupTabPersistsAndHiddenTabFallsBackWithoutChangingPreference() throws {
        let suite = "StartupTabTests.\(UUID())"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let settings = TabSettings(defaults: defaults)
        #expect(settings.initialTab == .discover)
        settings.startupTab = .localLibrary
        #expect(TabSettings(defaults: defaults).initialTab == .localLibrary)
        settings.setVisible(false, for: .localLibrary)
        settings.reorder(Array(MainTab.primary.reversed()))
        let restored = TabSettings(defaults: defaults)
        #expect(restored.initialTab == .purchased)
        #expect(restored.startupTab == .localLibrary)
        restored.setVisible(true, for: .localLibrary)
        #expect(restored.initialTab == .localLibrary)
    }

    @Test func persistsOrderVisibilityAndProtectsLastPage() throws {
        let suite = "TabSettingsTests.\(UUID())"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let settings = TabSettings(defaults: defaults)
        #expect(settings.visibleTabs == [.discover, .shuffle, .labels, .feed, .purchased, .localLibrary])
        settings.reorder(Array(MainTab.primary.reversed()))
        for tab in MainTab.primary { settings.setVisible(false, for: tab) }
        #expect(settings.visiblePrimary.count == 1)
        let restored = TabSettings(defaults: defaults)
        #expect(restored.order == settings.order)
        #expect(restored.visibleTabs == settings.visibleTabs)
        restored.reset()
        #expect(restored.visiblePrimary == MainTab.primary)
        #expect(restored.hidden.isEmpty)
    }
}

struct DiscoverSearchTests {
    @Test func searchSubmissionAndClearUseCurrentModel() {
        let model = SearchModel()
        model.query = "  Fairytales  "
        #expect(model.keyword == nil)
        model.submit()
        #expect(model.keyword == "Fairytales")
        let first = model.discs
        model.query = "云泠风"
        model.submit()
        #expect(model.keyword == "云泠风")
        #expect(model.discs !== first)
        model.query = ""
        model.clear()
        #expect(model.query.isEmpty)
        #expect(model.discs == nil)
    }
}
