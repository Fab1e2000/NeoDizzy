import Foundation

nonisolated struct DizzyCommunity: Sendable {
    static let shared = DizzyCommunity()
    let client: DizzyHTTPClient
    init(client: DizzyHTTPClient = .shared) { self.client = client }
    private var sessionID: String? { client.credentials.snapshot.cookies.first { $0.name == "sessionid" }?.value }
    private func discPath(_ id: String) -> String { "/d/\(DizzyURL.pathSegment(id))/" }
    func context(_ discID: String) async throws -> DiscCommunityContext {
        try CommunityPageParser.discContext(await client.html(path: discPath(discID), cachePolicy: .reloadIgnoringLocalCacheData))
    }
    func likes(_ discID: String) async throws -> DiscLikes {
        try await client.json(DiscLikes.self, path: "/albums/getthisdisclikes/", query: [.init(name: "discid", value: discID)], cachePolicy: .reloadIgnoringLocalCacheData)
    }
    func comments(_ discID: String, page: Int) async throws -> Page<DiscComment> {
        let offset = (page - 1) * 6
        return try CommunityJSON.comments(await client.data(path: "/albums/getdisccomment/", query: [.init(name: "discid", value: discID), .init(name: "l", value: String(offset)), .init(name: "r", value: String(offset + 6))], cachePolicy: .reloadIgnoringLocalCacheData), offset: offset)
    }
    func reviews(_ discID: String, page: Int) async throws -> Page<ReviewSummary> {
        let offset = (page - 1) * 3
        return try CommunityJSON.reviews(await client.data(path: "/getreviews/", query: [.init(name: "discid", value: discID), .init(name: "l", value: String(offset)), .init(name: "r", value: String(offset + 3))], cachePolicy: .reloadIgnoringLocalCacheData))
    }
    /// Fetch the current authenticated form before each mutation; never replay a toggle automatically.
    func toggleLike(_ discID: String, userID: Int) async throws -> DiscLikes {
        let session = sessionID
        let before = try await likes(discID)
        let ctx = try await context(discID)
        guard sessionID == session else { throw DizzyError.sessionExpired }
        try await mutate("/albums/ilikethisornot/", discID: discID, userID: userID, context: ctx)
        let after = try await likes(discID)
        guard after.ilikethis != before.ilikethis else { throw CommunityFailure.feedback("点赞状态未改变，请刷新后确认") }
        return after
    }
    func postComment(_ text: String, discID: String, userID: Int) async throws {
        let session = sessionID
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, trimmed.unicodeScalars.count <= 140 else { throw CommunityFailure.feedback("短评需要 1–140 字") }
        let ctx = try await context(discID)
        guard sessionID == session else { throw DizzyError.sessionExpired }
        guard ctx.canComment else { throw CommunityFailure.feedback("当前不能发表短评，请刷新页面") }
        try await mutate("/albums/postdisccomment/", discID: discID, userID: userID, context: ctx, extra: [("comment", trimmed)])
        let after = try await context(discID)
        guard after.userID == userID, after.myComment != nil else { throw CommunityFailure.feedback("短评结果尚未核验，请刷新确认，避免重复提交") }
    }
    func deleteComment(discID: String, userID: Int) async throws {
        let session = sessionID
        let ctx = try await context(discID)
        guard sessionID == session else { throw DizzyError.sessionExpired }
        guard ctx.myComment != nil else { throw CommunityFailure.feedback("没有可删除的自己的短评") }
        try await mutate("/albums/deletemycomment/", discID: discID, userID: userID, context: ctx)
        let after = try await context(discID)
        guard after.userID == userID, after.myComment == nil else { throw CommunityFailure.feedback("删除结果尚未核验，请刷新确认") }
    }
    private func mutate(_ path: String, discID: String, userID: Int, context: DiscCommunityContext, extra: [(String, String)] = []) async throws {
        guard context.userID == userID, let csrf = context.csrf else { throw DizzyError.sessionExpired }
        try Task.checkCancellation()
        let response = try await client.postForm(path: path, fields: [("discid", discID), ("csrfmiddlewaretoken", csrf)] + extra, referer: DizzyURL.disc(discID).absoluteString)
        guard !LoginPageParser.isLoginForm(response) else { throw DizzyError.sessionExpired }
        // Responses are not authoritative. Every caller verifies the fresh server state.
    }
    func followState(_ name: String) async throws -> CommunityPageParser.Follow? {
        try CommunityPageParser.follow(await client.html(path: "/l/\(DizzyURL.pathSegment(name))/", cachePolicy: .reloadIgnoringLocalCacheData))
    }
    func setFollowing(_ following: Bool, name: String, userID: Int) async throws -> Bool {
        let session = sessionID
        guard let before = try await followState(name), before.userID == userID else { throw DizzyError.sessionExpired }
        guard sessionID == session else { throw DizzyError.sessionExpired }
        if before.isFollowing == following { return following }
        try Task.checkCancellation()
        let path = "/l/\(DizzyURL.pathSegment(name))/"
        _ = try await client.html(path: path, query: [.init(name: before.query, value: nil)], cachePolicy: .reloadIgnoringLocalCacheData)
        guard let after = try await followState(name), after.userID == userID, after.isFollowing == following else { throw CommunityFailure.feedback("关注状态尚未核验，请刷新确认") }
        return after.isFollowing
    }
    func ranking() async throws -> [Supporter] {
        try CommunityPageParser.ranking(await client.html(path: "/ranking/"))
    }
    func profile(_ userID: Int, section: ProfileSection, page: Int) async throws -> CommunityProfile {
        try CommunityPageParser.profile(await client.html(path: "/u/\(userID)/\(section.rawValue)/", query: [.init(name: "page", value: String(page))], cachePolicy: .reloadIgnoringLocalCacheData), userID: userID, section: section)
    }
    func shuffle() async throws -> ShuffleTrack {
        let html = try await client.html(path: "/shuffle/", cachePolicy: .reloadIgnoringLocalCacheData)
        let token = try CommunityPageParser.csrf(html)
        let json = try await client.postForm(path: "/getatrack/", fields: [("csrfmiddlewaretoken", token)], referer: DizzyURL.page("/shuffle/").absoluteString)
        return try CommunityJSON.shuffle(Data(json.utf8))
    }
}
