import Foundation
import Testing
@testable import NeoDizzy

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

struct DizzyLabRouteTitleTests {
    @Test func routeTitlesUseSiteNames() {
        #expect(AppRoute.label(name: "Kirisense雾见").title == "Kirisense雾见")
        #expect(AppRoute.tag("电子").title == "#电子")
    }
}
