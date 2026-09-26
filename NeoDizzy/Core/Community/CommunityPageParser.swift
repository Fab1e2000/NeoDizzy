import Foundation
import SwiftSoup

nonisolated enum CommunityPageParser {
    static func csrf(_ html: String) throws -> String {
        let doc = try HTML.document(html, page: "community")
        if let value = try doc.select("input[name=csrfmiddlewaretoken]").first()?.attr("value"), !value.isEmpty { return value }
        if let match = html.firstMatch(of: #/['"]csrfmiddlewaretoken['"]\s*:\s*['"]([A-Za-z0-9]+)['"]/#) { return String(match.output.1) }
        throw DizzyError.parsing("community csrf")
    }
    static func discContext(_ html: String) throws -> DiscCommunityContext {
        let doc = try HTML.document(html, page: "disc community")
        guard try doc.select("#commentbox").first() != nil else { throw DizzyError.parsing("disc community") }
        let user = try LoggedInHomeParser.parse(html)?.userID
        let delete = try doc.select("[onclick*=deletemycomment]").first()
        let textBox = try doc.select("#comment_txt_box").first()
        let myText = delete == nil ? nil : HTML.multilineText(try doc.select("#commitbox p").first())
        return DiscCommunityContext(userID: user, csrf: try? csrf(html), myComment: myText,
                                    commentLimit: 140, canComment: textBox != nil)
    }
    struct Follow: Sendable {
        let isFollowing: Bool
        let query: String
        let userID: Int
    }
    static func follow(_ html: String) throws -> Follow? {
        let doc = try HTML.document(html, page: "label follow")
        guard let user = try LoggedInHomeParser.parse(html)?.userID else { return nil }
        guard let button = try doc.select("button[name^=likeit-]").first(),
              let href = try button.parent()?.attr("href"), href.hasPrefix("?"),
              let components = URLComponents(string: href), let query = components.queryItems,
              query.count == 1, query[0].value == nil else { throw DizzyError.parsing("label follow") }
        let name = query[0].name
        guard ["ilikeit", "dislike"].contains(name) else { throw DizzyError.parsing("label follow") }
        let control = try button.attr("name")
        guard (control == "likeit-on" && name == "ilikeit") || (control == "likeit-off" && name == "dislike") else { throw DizzyError.parsing("label follow") }
        return Follow(isFollowing: control == "likeit-off", query: name, userID: user)
    }
    static func ranking(_ html: String) throws -> [Supporter] {
        let doc = try HTML.document(html, page: "ranking")
        let result = try doc.select(".card-body:has(h1 a[href*=/u/])").array().compactMap { card -> Supporter? in
            guard let link = try card.select("h1 a").first(), let uid = LoggedInHomeParser.userID(fromHref: try link.attr("href")),
                  let rank = HTML.number(in: try card.select("h1").first()?.ownText()) else { return nil }
            return Supporter(rank: Int(rank), user: CommunityUser(id: uid, name: try link.text(), avatarURL: HTML.imageURL(try card.select("img").first())), bio: try card.select("p").first()?.text() ?? "")
        }
        guard !result.isEmpty else { throw DizzyError.parsing("ranking") }
        return result
    }
    static func profile(_ html: String, userID: Int, section: ProfileSection) throws -> CommunityProfile {
        let doc = try HTML.document(html, page: "profile")
        guard let heading = try doc.select("h1").first(),
              try doc.select("a[href*=/u/\(userID)/music]").first() != nil else { throw DizzyError.parsing("profile") }
        let user = CommunityUser(id: userID, name: try heading.text(), avatarURL: HTML.imageURL(try heading.parent()?.parent()?.select("img").first()))
        let cards = try doc.select("a[href*=/d/]:has(.album_cover)").array()
        let discs = try cards.compactMap { link -> DiscSummary? in
            guard let id = HTML.discID(fromHref: try link.attr("href")) else { return nil }
            let footer = try link.parent()?.parent()?.select(".card-footer").first()
            let title = try footer?.select("[onclick^=updateplayer]").first()?.attr("title")
                ?? footer?.select("h4[title]").first()?.attr("title") ?? footer?.select("h4").first()?.text() ?? id
            return DiscSummary(id: id, title: title, coverURL: HTML.imageURL(try link.select(".album_cover img").first()), labelName: try footer?.select("a[href*=/l/]").first()?.text().mapAt, isOwned: false)
        }
        let labels = try doc.select("#album .card-body:has(a[href*=/l/])").array().compactMap { card -> SearchLabel? in
            guard let link = try card.select("a[href*=/l/]").first(), let name = HTML.labelName(fromHref: try link.attr("href")) else { return nil }
            return SearchLabel(name: name, coverURL: HTML.imageURL(try link.select("img").first()), description: "")
        }
        var seen = Set<Int>()
        let reviews = try doc.select("#album a[href*=/review/]").array().compactMap { link -> ReviewSummary? in
            guard let match = try link.attr("href").firstMatch(of: #//review/(\d+)/#), let id = Int(match.output.1), seen.insert(id).inserted else { return nil }
            let title = try link.text()
            return ReviewSummary(id: id, title: title.isEmpty ? "repo" : title, excerpt: "", user: user, date: nil)
        }
        return CommunityProfile(user: user, bio: try heading.parent()?.select("p").first()?.text() ?? "", joined: try heading.parent()?.select("h2").first()?.text() ?? "", discs: discs, labels: section == .following ? labels : [], reviews: reviews, hasMore: HTML.hasNextPage(doc))
    }
}
private nonisolated extension String {
    var mapAt: String { HTML.stripAt(self) }
}

nonisolated extension CommunityPageParser {
    static func review(_ html: String) throws -> ReviewDetail {
        let doc = try HTML.document(html, page: "review")
        guard let body = try doc.select("#reviewlikes").first()?.parent()?.parent(),
              let title = try body.select("h3").first()?.text(),
              let content = try body.select("p.truncate-limit").first() else { throw DizzyError.parsing("review") }
        let author = try doc.select(".media:has(a[href*=/u/])").first()
        let link = try author?.select(".media-body a[href*=/u/]").first()
        let user: CommunityUser?
        if let link, let uid = LoggedInHomeParser.userID(fromHref: try link.attr("href")) {
            user = CommunityUser(id: uid, name: try link.text(), avatarURL: HTML.imageURL(try author?.select("img").first()))
        } else { user = nil }
        return ReviewDetail(title: title, user: user, text: HTML.multilineText(content), images: try body.select("img:not(#imagepreview)").array().compactMap(HTML.imageURL))
    }
}
