import Foundation
import Testing
@testable import NeoDizzy

/// 每个解析器对照一份真实页面样本。网站改版时这里最先失败。
struct PageParserTests {
    @Test func homeHasDealsAndPacks() throws {
        let home = try HomePageParser.parse(Fixture.text("home.html"))

        let deal = try #require(home.deals.first)
        #expect(home.deals.count == 1)
        #expect(deal.disc.id == "KSEP-001")
        #expect(deal.disc.title == "RE：Spring")
        #expect(deal.disc.price == .deal(original: 40, current: 18))
        #expect(deal.deadline == "2026年9月30日 截止")

        #expect(home.packs.count == 40)
        let pack = try #require(home.packs.first)
        #expect(pack.id == "obs-PACK01")
        #expect(pack.title == "【实体】Quiddity:2")
        #expect(pack.labelName == "obscuRE TRAX")
        #expect(pack.price == 85)
        #expect(pack.coverURL != nil)
    }

    @Test func labelPageHasProfilePacksAndAllDiscs() throws {
        let label = try LabelPageParser.parse(Fixture.text("label.html"))
        #expect(label.name == "obscuRE TRAX")
        #expect(label.coverURL?.lastPathComponent == "封面logo_00000.png")
        #expect(label.followerCount == 317)
        #expect(label.history.first == "obscuRE TRAX成立于2024年06月21日")
        // `<br>` 保留为换行，两段简介之间空一行。
        #expect(label.description.hasPrefix("Team obscuRE，多元化电子音乐社团\n\n投稿请联系\n"))
        #expect(label.description.contains("\n\nB站："))

        #expect(label.packs.map(\.id) == ["obs-PACK01"])
        #expect(label.discs.count == 8)
        #expect(label.discs.first?.id == "obs-CD06BP")
        #expect(label.discs.first?.title == "【实体】Quiddity:2「PART B」")
        #expect(label.discs.first?.price == .price(45))
        #expect(label.discs.last?.price == .free)
        #expect(label.discs.allSatisfy { $0.labelName == "obscuRE TRAX" && $0.coverURL != nil })
    }

    @Test func tagPageHasOnePageOfDiscs() throws {
        let page = try TagPageParser.parse(Fixture.text("tag.html"))
        #expect(page.items.count == 24)
        #expect(page.hasMore)
        #expect(page.items.first?.id == "obs-CD06BP")
        #expect(page.items[1].title == "Glassy Tears 44.1kHz")
        #expect(page.items.allSatisfy { $0.coverURL != nil })
    }

    @Test func searchHasLabelsAndDiscsButSkipsUsers() throws {
        let results = try SearchPageParser.parse(Fixture.text("search.html"))
        #expect(results.labels.map(\.name) == ["雪人Snowman"])
        #expect(results.discs.count == 10)
        #expect(results.hasMore)

        let first = try #require(results.discs.first)
        #expect(first.disc.id == "obs-CD06BP")
        #expect(first.disc.labelName == "obscuRE TRAX")
        #expect(first.excerpt.hasPrefix("来自obscuRE TRAX"))
        #expect(results.discs.allSatisfy { $0.excerpt.count <= SearchPageParser.excerptLimit + 1 })
    }

    /// 摘要合并换行和多余空白，超过上限时截断并加省略号，避免卡片排版整段介绍。
    @Test func searchExcerptIsShortSingleParagraph() {
        #expect(SearchPageParser.excerpt("  第一行\n\n第二行   结尾 ") == "第一行 第二行 结尾")
        #expect(SearchPageParser.excerpt(nil) == "")
        let long = SearchPageParser.excerpt(String(repeating: "东方同人 ", count: 100))
        #expect(long.count == SearchPageParser.excerptLimit + 1)
        #expect(long.hasSuffix("…"))
    }

    @Test func packPageListsIncludedDiscsAndPrice() throws {
        let pack = try PackPageParser.parse(Fixture.text("pack.html"), id: "PNP-001")
        #expect(pack.title == "Pure Nebula 3 in 1")
        #expect(pack.labelName == "琉净星云")
        #expect(pack.price == 84)
        #expect(pack.offer == "购买此pack以20%折扣的价格（原价：105.0元）")
        #expect(pack.discs.map(\.id) == ["PNCD-0002", "PNCD-0003", "PNCD-001"])
        #expect(pack.discs.first?.title == "Majestic Glimpse")
        #expect(pack.description.hasPrefix("琉净星云Pure Nebula三专里程碑特惠\n包含以下电子版：\n1.New Age"))
    }

    @Test func discPageGivesTrackDurations() throws {
        let durations = try DiscPageParser.trackDurations(Fixture.text("disc.html"))
        #expect(durations.count == 11)
        #expect(durations["1"] == 155)
        // 标题里带括号的曲目，取最后一对括号里的时长。
        #expect(durations["2"] == 208)
    }

    @Test func siteErrorPageIsAParsingFailure() {
        let errorPage = "<html><head><title>出错了！ - dizzylab</title></head><body>出错了！</body></html>"
        #expect(throws: DizzyError.parsing("label")) {
            try LabelPageParser.parse(errorPage)
        }
        #expect(throws: DizzyError.parsing("search")) {
            try SearchPageParser.parse(errorPage)
        }
    }
}
