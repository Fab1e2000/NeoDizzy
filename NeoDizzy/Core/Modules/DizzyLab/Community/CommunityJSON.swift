import Foundation
import SwiftSoup

/// Website arrays are positional. Reject mismatched arrays instead of attributing text to the wrong user.
nonisolated enum CommunityJSON {
    private static func object(_ data: Data) throws -> [String: Any] {
        guard let result = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw DizzyError.parsing("community")
        }
        return result
    }
    static func plain(_ value: String) -> String {
        guard let doc = try? SwiftSoup.parseBodyFragment(value) else { return value }
        return HTML.multilineText(doc.body())
    }
    static func comments(_ data: Data, offset: Int) throws -> Page<DiscComment> {
        let obj = try object(data)
        guard let texts = obj["disc_comment"] as? [String], let names = obj["user_names"] as? [String],
              let urls = obj["user_url"] as? [String], let avatars = obj["avatar_url"] as? [String],
              let more = obj["canshowmore"] as? Bool,
              texts.count == names.count, texts.count == urls.count, texts.count == avatars.count else {
            throw DizzyError.parsing("comments")
        }
        let redeemed = obj["redeemit"] as? [Bool] ?? []
        let prepaid = obj["prebuyer"] as? [Bool] ?? []
        let items = try texts.indices.map { i -> DiscComment in
            guard let uid = LoggedInHomeParser.userID(fromHref: urls[i]) else { throw DizzyError.parsing("comment user") }
            return DiscComment(id: "\(offset + i)-\(uid)", user: CommunityUser(id: uid, name: plain(names[i]), avatarURL: DizzyURL.image(avatars[i])), text: plain(texts[i]), badge: redeemed.indices.contains(i) && redeemed[i] ? "兑换支持" : (prepaid.indices.contains(i) && prepaid[i] ? "预购支持" : nil))
        }
        return Page(items: items, hasMore: more && !items.isEmpty)
    }
    static func reviews(_ data: Data) throws -> Page<ReviewSummary> {
        let obj = try object(data)
        guard let ids = obj["review_id"] as? [Int], let titles = obj["review_title"] as? [String],
              let descriptions = obj["review_desc"] as? [String], let users = obj["user_id"] as? [Int],
              let names = obj["user_name"] as? [String], let avatars = obj["user_avatar"] as? [String],
              let more = obj["canshowmore"] as? Bool,
              [titles.count, descriptions.count, users.count, names.count, avatars.count].allSatisfy({ $0 == ids.count }) else {
            throw DizzyError.parsing("reviews")
        }
        let dates = obj["add_date"] as? [String] ?? []
        return Page(items: ids.indices.map { i in
            ReviewSummary(id: ids[i], title: plain(titles[i]), excerpt: plain(descriptions[i]), user: CommunityUser(id: users[i], name: plain(names[i]), avatarURL: DizzyURL.image(avatars[i])), date: dates.indices.contains(i) ? dates[i] : nil)
        }, hasMore: more && !ids.isEmpty)
    }
    static func shuffle(_ data: Data) throws -> ShuffleTrack {
        let obj = try object(data)
        guard let disc = obj["discid"] as? String, !disc.isEmpty,
              let title = obj["thistrack"] as? String, let album = obj["disctitle"] as? String,
              let raw = obj["thisurl"] as? String, let url = URL(string: raw),
              url.scheme == "https", url.host == "streaming.dizzylab.net",
              let number = url.deletingPathExtension().lastPathComponent.firstMatch(of: #/^\d+$/#).map({ String($0.output) }) else {
            throw DizzyError.parsing("shuffle")
        }
        return ShuffleTrack(track: Track(discID: disc, number: number, title: title.replacing(#/^\d+\.\s*/#, with: ""), artists: obj["thisauther"] as? String ?? "", albumTitle: album, coverURL: DizzyURL.image(obj["disccover"] as? String ?? ""), duration: nil), stream: url, label: obj["disclabel"] as? String ?? "", tags: obj["taglist"] as? [String] ?? [])
    }
}
