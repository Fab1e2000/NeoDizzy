import Foundation
import Testing
@testable import NeoDizzy

struct JSONDecodingTests {
    @Test func discListMapsFieldsAndPrices() throws {
        let response = try JSONDecoder().decode(DiscListResponse.self, from: Fixture.data("getdiscs.json"))
        #expect(response.total_count == 1572)
        let discs = response.discs.map(\.summary)
        #expect(discs.count == 6)

        let physical = try #require(discs.first)
        #expect(physical.id == "obs-CD06BP")
        #expect(physical.labelName == "obscuRE TRAX")
        #expect(physical.labelID == 440)
        #expect(physical.price == .price(45))
        #expect(physical.tags.contains("Frenchcore"))

        #expect(discs[1].id == "fx4")
        #expect(discs[1].price == .free)
    }

    @Test func discDetailSplitsTracksAndSignedStreams() throws {
        let detail = try JSONDecoder().decode(DiscDetailResponse.self, from: Fixture.data("getthisdicsinfo.json")).detail
        #expect(detail.summary.title == "Glassy Tears 44.1kHz")
        #expect(detail.releaseDate == "2026-06-28")
        #expect(detail.tracks.count == 11)

        let first = try #require(detail.tracks.first)
        #expect(first.id == "fx4/1")
        #expect(first.title == "Story Left in Snow")
        #expect(first.artists == "Chikanya")
        #expect(first.duration == nil)

        let stream = try #require(detail.streams["1"])
        #expect(DizzyURL.isPreviewStream(stream))
        #expect(detail.streams.count == 11)
    }

    @Test func labelListCompletesRelativeCoverPaths() throws {
        let response = try JSONDecoder().decode(LabelListResponse.self, from: Fixture.data("getlabels.json"))
        #expect(response.total_count == 670)
        let labels = response.labels.map(\.summary)
        let dream = try #require(labels.first { $0.name == "梦境少女" })
        #expect(dream.recentDiscs.map(\.id) == ["2026-1005", "2026-1004"])
        #expect(dream.recentDiscs.first?.coverURL?.absoluteString
            == "https://cdn.dizzylab.net/media/cover/2026-1005.jpg!cover")
        #expect(labels.first?.recentDiscs.isEmpty == true)
    }

    @Test(arguments: [
        (0.0, true, false, PriceTag.free),
        (0.0, false, false, PriceTag.free),
        (30.0, false, false, PriceTag.redeem),
        (30.0, false, true, PriceTag.price(30)),
        (30.0, true, false, PriceTag.price(30)),
    ])
    func priceFollowsSiteRules(price: Double, onSell: Bool, preselling: Bool, expected: PriceTag) {
        #expect(PriceTag(price: price, onSell: onSell, isPreselling: preselling) == expected)
    }

    @Test func pricesDropTrailingZeros() {
        #expect(PriceTag.price(45).text == "¥45")
        #expect(PriceTag.deal(original: 40, current: 18).text == "¥18")
        #expect(PriceTag.yuan(4.5) == "¥4.5")
    }
}
