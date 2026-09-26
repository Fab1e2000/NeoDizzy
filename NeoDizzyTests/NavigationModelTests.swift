import Testing
@testable import NeoDizzy

struct NavigationModelTests {
    @Test func searchStaysOutOfPrimaryTabs() {
        #expect(!MainTab.primary.contains(.search))
        #expect(Set(MainTab.primary).union([.search]) == Set(MainTab.allCases))
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
