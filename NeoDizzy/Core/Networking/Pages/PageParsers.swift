import Foundation
import SwiftSoup

/// 首页：`#deal`（限时优惠）和 `#pack` 两个面板直接写在 HTML 里；专辑列表由脚本调 `getdiscs` 加载。
nonisolated enum HomePageParser {
    static func parse(_ html: String) throws -> HomeShowcase {
        try HTML.parsing("home") {
            let document = try HTML.document(html, page: "home")
            guard let dealPane = try document.select("#deal").first(),
                  let packPane = try document.select("#pack").first() else {
                throw DizzyError.parsing("home")
            }
            let deals = try dealPane.select(".card-body").array().compactMap { card -> Deal? in
                guard let link = try card.select("a[href*=/d/]").first(),
                      let id = HTML.discID(fromHref: try link.attr("href")) else { return nil }
                let disc = DiscSummary(
                    id: id,
                    title: try card.select("p.text-light").first()?.text() ?? id,
                    coverURL: HTML.imageURL(try card.select("img").first()),
                    price: HTML.price(try card.select("h4").first())
                )
                return Deal(disc: disc, deadline: try card.select(".badge").first()?.text())
            }
            let packs = try packPane.select(".card-body").array().compactMap(HTML.packCard)
            return HomeShowcase(deals: deals, packs: packs)
        }
    }
}

/// 社团页 `/l/<名字>/`：页头、pack 和全部作品。页面里的 `?page=` 翻的是关注者头像，不是作品。
nonisolated enum LabelPageParser {
    static func parse(_ html: String) throws -> LabelPage {
        try HTML.parsing("label") {
            let document = try HTML.document(html, page: "label")
            guard let title = try document.select("#labeltitle").first() else {
                throw DizzyError.parsing("label")
            }
            let name = try title.text()
            let description = [
                HTML.multilineText(try document.select("#labeldesp").first()),
                HTML.multilineText(try document.select("#labeldesp2").first()),
            ].filter { !$0.isEmpty }.joined(separator: "\n\n")

            // 封面在标题所在列的前一列。
            let cover = HTML.imageURL(try title.parent()?.previousElementSibling()?.select("img").first())

            let followers = try document.select("h2").array()
                .compactMap { try $0.text() }
                .first { $0.contains("关注") }
                .flatMap { HTML.number(in: $0) }
                .map { Int($0) }

            let history = try document.select("h3.text-muted").array().map { try $0.text() }
            let packs = try document.select("#divscroll_pack .card-body").array().compactMap(HTML.packCard)

            // 作品卡片：封面链接在 card-body 里，标题和价格在同一张卡的 card-footer 里。
            let discs = try document.select("a[href*=/d/]:has(.album_cover)").array().compactMap { link -> DiscSummary? in
                guard let id = HTML.discID(fromHref: try link.attr("href")) else { return nil }
                let footer = try link.parent()?.parent()?.select(".card-footer").first()
                let heading = try footer?.select("h4.text-truncate").first()?.text()
                return DiscSummary(
                    id: id,
                    title: heading?.trimmingCharacters(in: .whitespaces) ?? id,
                    coverURL: HTML.imageURL(try link.select("img").first()),
                    labelName: name,
                    price: HTML.price(try footer?.select("h4:not(.text-truncate)").first())
                )
            }

            return LabelPage(
                name: name,
                coverURL: cover,
                description: description,
                followerCount: followers,
                history: history,
                packs: packs,
                discs: discs
            )
        }
    }
}

/// 标签页 `/albums/tags/?tag=<标签>&page=<n>`：每页 24 张，卡片只有封面和标题。
nonisolated enum TagPageParser {
    static func parse(_ html: String) throws -> Page<DiscSummary> {
        try HTML.parsing("tag") {
            let document = try HTML.document(html, page: "tag")
            // 「标签为…的作品:」标题，用来确认页面结构没变。
            guard try document.select("p.card-title").first() != nil else {
                throw DizzyError.parsing("tag")
            }
            let discs = try document.select(".card-body").array().compactMap { card -> DiscSummary? in
                // 卡片的第一层就是专辑链接；嵌套更深的链接属于别的区域。
                guard let link = card.children().array().first(where: { $0.tagName() == "a" }),
                      let id = HTML.discID(fromHref: try link.attr("href")) else { return nil }
                return DiscSummary(
                    id: id,
                    title: try card.select("p").first()?.text() ?? id,
                    coverURL: HTML.imageURL(try link.select("img").first())
                )
            }
            return Page(items: discs, hasMore: HTML.hasNextPage(document))
        }
    }
}

/// 搜索页 `/search/?s=<关键词>&page=<n>`：第一页依次是「社团」「作品」「用户」三组，之后每页只有作品（10 张）。
nonisolated enum SearchPageParser {
    /// 结果卡片只显示两行摘要。网页给的是整段介绍（有的长达几百字），整段交给文字排版时
    /// 每次绘制、悬停和网格测量都要重排全文，Mac 上滚动搜索结果会明显卡顿。
    static let excerptLimit = 120

    static func excerpt(_ text: String?) -> String {
        let words = (text ?? "").split(whereSeparator: \.isWhitespace)
        var result = ""
        for word in words {
            if !result.isEmpty { result += " " }
            result += word
            if result.count > excerptLimit { return String(result.prefix(excerptLimit)) + "…" }
        }
        return result
    }

    static func parse(_ html: String) throws -> SearchResults {
        try HTML.parsing("search") {
            let document = try HTML.document(html, page: "search")
            // 正文里的搜索框（导航栏里的搜索框每一页都有，不能用来判断）。
            guard try document.select(".form-group input[name=s]").first() != nil else {
                throw DizzyError.parsing("search")
            }
            let labels = try document.select("a[href*=/l/]:has(h1)").array().compactMap { link -> SearchLabel? in
                let name = try link.select("h1").first()?.text()
                    ?? HTML.labelName(fromHref: try link.attr("href"))
                guard let name else { return nil }
                return SearchLabel(
                    name: name,
                    coverURL: HTML.imageURL(try link.select("img").first()),
                    description: excerpt(try link.select("h3.truncate-limit").first()?.text())
                )
            }
            let discs = try document.select("a[href*=/d/]:has(h1)").array().compactMap { link -> SearchDisc? in
                guard let id = HTML.discID(fromHref: try link.attr("href")) else { return nil }
                let disc = DiscSummary(
                    id: id,
                    title: try link.select("h1").first()?.text() ?? id,
                    coverURL: HTML.imageURL(try link.select("img").first()),
                    labelName: try link.select("h3:not(.truncate-limit)").first()?.text()
                )
                return SearchDisc(disc: disc, excerpt: excerpt(try link.select("h3.truncate-limit").first()?.text()))
            }
            let users = try document.select("a[href*=/u/]:has(h1)").array().compactMap { link -> CommunityUser? in
                guard let id = LoggedInHomeParser.userID(fromHref: try link.attr("href")) else { return nil }
                return CommunityUser(id: id, name: try link.select("h1").first()?.text() ?? String(id), avatarURL: HTML.imageURL(try link.select("img").first()))
            }
            return SearchResults(labels: labels, discs: discs, hasMore: HTML.hasNextPage(document), users: users)
        }
    }
}

/// pack 页 `/pack/?pk=<id>`。
nonisolated enum PackPageParser {
    static func parse(_ html: String, id: String) throws -> PackDetail {
        try HTML.parsing("pack") {
            let document = try HTML.document(html, page: "pack")
            guard let title = try document.select("h1").first()?.text() else {
                throw DizzyError.parsing("pack")
            }

            // 说明里的专辑链接带标题，封面区的链接带封面，按 ID 合并。
            var titles: [String: String] = [:]
            for link in try document.select("p.card-text a[href*=/d/]").array() {
                if let id = HTML.discID(fromHref: try link.attr("href")) {
                    titles[id] = try link.text()
                }
            }
            let labelName = try document.select("p.text-info").first()?.text()
            let discs = try document.select(".card-footer a[href*=/d/]:has(img)").array().compactMap { link -> DiscSummary? in
                guard let discID = HTML.discID(fromHref: try link.attr("href")) else { return nil }
                return DiscSummary(
                    id: discID,
                    title: titles[discID] ?? discID,
                    coverURL: HTML.imageURL(try link.select("img").first()),
                    labelName: labelName
                )
            }

            let offer = try document.select("p.card-text").array()
                .map { try $0.text() }
                .first { $0.contains("pack") }
                .map { text in
                    // 「购买此pack以20%折扣的价格（原价：105.0元）获得：专辑A，专辑B，」只保留前半句。
                    text.components(separatedBy: "获得").first?.trimmingCharacters(in: .whitespaces) ?? text
                }

            let checkout = try document.select("a[href*=checkout_alipay]").first()?.attr("href")
            let price = checkout.flatMap { HTML.queryValue("price", in: $0) }.flatMap(Double.init)

            return PackDetail(
                id: id,
                title: title,
                coverURL: HTML.imageURL(try document.select(".card-head img").first()),
                labelName: labelName,
                discs: discs,
                price: price,
                offer: offer,
                description: HTML.multilineText(try document.select("p.text-left").last())
            )
        }
    }
}

/// 专辑页 `/d/<id>/`：只用来补曲目时长，其余信息走 JSON 接口。
/// 曲目标题写作 `1. Story Left in Snow - Chikanya (02:35)`。
nonisolated enum DiscPageParser {
    static func trackDurations(_ html: String) throws -> [String: TimeInterval] {
        try HTML.parsing("disc") {
            let document = try HTML.document(html, page: "disc")
            var durations: [String: TimeInterval] = [:]
            for title in try document.select("li[data-audio] .t-title").array() {
                let text = try title.text()
                guard let match = text.firstMatch(of: #/^(\d+)\..*\((?:(\d+):)?(\d{1,2}):(\d{2})\)\s*$/#) else {
                    continue
                }
                let hours = match.output.2.flatMap { Double($0) } ?? 0
                let minutes = Double(match.output.3) ?? 0
                let seconds = Double(match.output.4) ?? 0
                durations[String(match.output.1)] = hours * 3600 + minutes * 60 + seconds
            }
            return durations
        }
    }
}
