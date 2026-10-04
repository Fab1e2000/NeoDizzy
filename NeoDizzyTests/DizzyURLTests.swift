import Foundation
import Testing
@testable import NeoDizzy

struct DizzyURLTests {
    @Test func relativeCoverPathsGoToCDNWithThumbnailStyle() {
        #expect(DizzyURL.image("cover/2026-1005.jpg")?.absoluteString
            == "https://cdn.dizzylab.net/media/cover/2026-1005.jpg!cover")
    }

    @Test func absoluteCoverWithChineseFileNameIsEscaped() throws {
        let url = try #require(DizzyURL.image("https://cdn.dizzylab.net/media/cover/海报_2.jpg!cover"))
        #expect(url.absoluteString == "https://cdn.dizzylab.net/media/cover/%E6%B5%B7%E6%8A%A5_2.jpg!cover")
    }

    @Test func emptyAndPlaceholderImagesAreIgnored() throws {
        #expect(DizzyURL.image("  ") == nil)
        #expect(DizzyURL.image(nil) == nil)
        let holder = try #require(DizzyURL.image("https://cdn.dizzylab.net/static/holder_cover.jpg"))
        #expect(DizzyURL.isPlaceholderImage(holder))
    }

    @Test func pngAvatarsBypassLossyCDNStyle() throws {
        let styled = try #require(DizzyURL.image("https://cdn.dizzylab.net/media/label_cover/1_uBbFeP3.png!cover"))
        #expect(DizzyURL.avatar(styled)?.absoluteString == "https://cdn.dizzylab.net/media/label_cover/1_uBbFeP3.png")
        // 普通图片解析仍保留样式，只有头像视图选择原图。
        #expect(styled.absoluteString.hasSuffix("!cover"))
        let escaped = try #require(URL(string: "https://cdn.dizzylab.net/media/avatars/%E6%98%9F.PNG%21cover?token=a%2Bb#icon"))
        #expect(DizzyURL.avatar(escaped)?.path == "/media/avatars/星.PNG")
        #expect(DizzyURL.avatar(escaped)?.query == "token=a%2Bb")
        #expect(DizzyURL.avatar(escaped)?.fragment == "icon")
    }

    @Test func avatarURLLeavesUnrelatedResourcesUntouched() {
        #expect(DizzyURL.avatar(nil) == nil)
        for address in [
            "https://cdn.dizzylab.net/media/avatars/photo.jpg!cover",
            "https://cdn.dizzylab.net/media/avatars/logo.png!other",
            "https://cdn.dizzylab.net/media/avatars/logo.png",
            "https://example.com/media/avatars/logo.png!cover",
            "https://cdn.dizzylab.net/static/logo.png!cover"
        ] {
            let url = URL(string: address)
            #expect(DizzyURL.avatar(url) == url)
        }
    }

    @Test func pathSegmentsAndQueryValuesAreFullyEscaped() {
        #expect(DizzyURL.label("obscuRE TRAX").absoluteString == "https://www.dizzylab.net/l/obscuRE%20TRAX/")
        #expect(DizzyURL.label("A/B").absoluteString == "https://www.dizzylab.net/l/A%2FB/")
        // Django 把 `+` 当空格，`&` 会截断参数，都必须转义。
        #expect(DizzyURL.tag("R&B+").absoluteString == "https://www.dizzylab.net/albums/tags/?tag=R%26B%2B")
        #expect(DizzyURL.tag("电子").absoluteString == "https://www.dizzylab.net/albums/tags/?tag=%E7%94%B5%E5%AD%90")
    }

    @Test func streamURLTellsPreviewAndExpiry() throws {
        let preview = try #require(URL(string: "https://streaming.dizzylab.net/202609261738/47b9396aaf5e70bc3fc219be690419bd/fx4/preview/1.mp3"))
        let full = try #require(URL(string: "https://streaming.dizzylab.net/202609261738/47b9396aaf5e70bc3fc219be690419bd/obs-CD06BP/full/1.mp3"))
        #expect(DizzyURL.isPreviewStream(preview))
        #expect(!DizzyURL.isPreviewStream(full))

        // 时间戳是东八区的过期时间：17:38 CST = 09:38 UTC。
        let expiry = try #require(DizzyURL.streamExpiry(preview))
        #expect(expiry == Date(timeIntervalSince1970: 1_790_415_480))
    }

    @Test func linkHelpersReadIDsFromSiteHrefs() {
        #expect(HTML.discID(fromHref: "/d/obs-CD06BP") == "obs-CD06BP")
        #expect(HTML.discID(fromHref: "https://www.dizzylab.net/d/fx4/") == "fx4")
        #expect(HTML.labelName(fromHref: "/l/雪人Snowman") == "雪人Snowman")
        #expect(HTML.labelName(fromHref: "/l/obscuRE%20TRAX/") == "obscuRE TRAX")
        #expect(HTML.packID(fromHref: "/pack/?pk=obs-PACK01") == "obs-PACK01")
        #expect(HTML.queryValue("price", in: "/albums/checkout_alipay/?id=PNP-001&q=1&type=pack&price=84.0") == "84.0")
    }
}
