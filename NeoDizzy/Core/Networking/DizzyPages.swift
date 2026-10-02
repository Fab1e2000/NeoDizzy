import Foundation

/// 没有 JSON 接口、需要解析 HTML 的页面。解析放到后台执行，不占用主线程。
nonisolated struct DizzyPages: Sendable {
    static let shared = DizzyPages()

    let client: DizzyHTTPClient

    init(client: DizzyHTTPClient = .shared) {
        self.client = client
    }

    func home() async throws -> HomeShowcase {
        let html = try await client.html(path: "/")
        return try await Self.parse { try HomePageParser.parse(html) }
    }

    func label(name: String) async throws -> LabelPage {
        let html = try await client.html(path: "/l/\(DizzyURL.pathSegment(name))/", cachePolicy: .reloadIgnoringLocalCacheData)
        return try await Self.parse { try LabelPageParser.parse(html) }
    }

    func tag(_ tag: String, page: Int) async throws -> Page<DiscSummary> {
        let html = try await client.html(path: "/albums/tags/", query: [
            URLQueryItem(name: "tag", value: tag),
            URLQueryItem(name: "page", value: String(page)),
        ])
        return try await Self.parse { try TagPageParser.parse(html) }
    }

    func search(_ keyword: String, page: Int) async throws -> SearchResults {
        let html = try await client.html(path: "/search/", query: [
            URLQueryItem(name: "s", value: keyword),
            URLQueryItem(name: "page", value: String(page)),
        ])
        return try await Self.parse { try SearchPageParser.parse(html) }
    }

    func pack(id: String) async throws -> PackDetail {
        let html = try await client.html(path: "/pack/", query: [URLQueryItem(name: "pk", value: id)])
        return try await Self.parse { try PackPageParser.parse(html, id: id) }
    }

    /// 已购专辑，一页一页地翻。这个页面公开可见，不需要会话 Cookie。
    func purchases(userID: Int, page: Int) async throws -> Page<PurchasedDisc> {
        try await profileMusic(userID: userID, page: page).purchases
    }

    func profileMusic(userID: Int, page: Int = 1) async throws -> ProfileMusicPageParser.Result {
        let html = try await client.html(path: "/u/\(userID)/music/", query: page > 1 ? [URLQueryItem(name: "page", value: String(page))] : [], cachePolicy: .reloadIgnoringLocalCacheData)
        return try await Self.parse { try ProfileMusicPageParser.parse(html) }
    }

    /// Signed download menus must be fetched immediately before starting or retrying a download.
    func downloadOptions(discID: String, gift: Bool = false) async throws -> [DownloadOption] {
        guard client.credentials.cookieHeader() != nil else { throw DizzyError.notLoggedIn }
        let html = try await client.html(path: "/d/\(DizzyURL.pathSegment(discID))/", cachePolicy: .reloadIgnoringLocalCacheData)
        return try await Self.parse { try DownloadPageParser.parse(html, discID: discID, gift: gift) }
    }

    /// Price and sale status can change; never reuse a cached checkout offer.
    func purchaseOffer(discID: String, isOwned: Bool) async throws -> PurchaseOffer {
        guard client.credentials.cookieHeader() != nil else { throw DizzyError.notLoggedIn }
        let html = try await client.html(path: "/d/\(DizzyURL.pathSegment(discID))/", cachePolicy: .reloadIgnoringLocalCacheData)
        let offer = try await Self.parse { try PurchasePageParser.parse(html, discID: discID, isOwned: isOwned) }
        guard !offer.requiresLogin else { throw DizzyError.notLoggedIn }
        return offer
    }

    /// 曲号 → 完整版时长。
    func trackDurations(discID: String) async throws -> [String: TimeInterval] {
        let html = try await client.html(path: "/d/\(DizzyURL.pathSegment(discID))/")
        return try await Self.parse { try DiscPageParser.trackDurations(html) }
    }

    @concurrent
    private static func parse<T: Sendable>(_ work: @Sendable () throws -> T) async throws -> T {
        try work()
    }
}
