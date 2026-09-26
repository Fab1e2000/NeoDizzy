import Foundation
import Testing
@testable import NeoDizzy

struct CommunityTests {
    @Test func commentsKeepAuthorAndTextAligned() throws {
        let data = try Fixture.data("community-comments.json")
        let page = try CommunityJSON.comments(data, offset: 6)
        #expect(page.items.count == 1 && !page.hasMore)
        #expect(page.items[0].user.id == 42)
        #expect(page.items[0].text == "第一行\n第二行 & 音乐")
        #expect(page.items[0].badge == "预购支持")
        #expect(page.items[0].id == "6-42")
        var obj = try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
        obj["user_names"] = []
        #expect(throws: (any Error).self) { try CommunityJSON.comments(JSONSerialization.data(withJSONObject: obj), offset: 0) }
        #expect(throws: (any Error).self) { try CommunityJSON.comments(Data("<html>出错了</html>".utf8), offset: 0) }
    }
    @Test func reviewsRejectPartialParallelArrays() throws {
        let obj: [String: Any] = ["review_id": [7], "review_title": ["标题"], "review_desc": ["<p>内容</p>"], "user_id": [42], "user_name": ["用户"], "user_avatar": [""], "canshowmore": true]
        let page = try CommunityJSON.reviews(JSONSerialization.data(withJSONObject: obj))
        #expect(page.items[0].id == 7 && page.items[0].user?.id == 42 && page.hasMore)
        var broken = obj; broken["user_id"] = []
        #expect(throws: (any Error).self) { try CommunityJSON.reviews(JSONSerialization.data(withJSONObject: broken)) }
    }
    @Test func parsesRankReviewAndEmptyProfileFromPageStructure() throws {
        let rank = try CommunityPageParser.ranking(Fixture.text("community-ranking.html"))
        #expect(rank.first?.rank == 1 && rank.first?.user.id == 42)
        #expect(rank.count > 10)
        let review = try CommunityPageParser.review(Fixture.text("community-review.html"))
        #expect(review.title == "长评样本")
        #expect(review.user?.id == 42 && review.text == "长评样本！")
        let profile = try CommunityPageParser.profile(Fixture.text("community-profile-empty.html"), userID: 42, section: .review)
        #expect(profile.user.name == "测试用户" && profile.reviews.isEmpty && !profile.hasMore)
        let reviewed = try CommunityPageParser.profile(Fixture.text("community-profile-reviews.html"), userID: 42, section: .review)
        #expect(reviewed.reviews.count == 1 && reviewed.reviews[0].id == 100)
        #expect(throws: DizzyError.self) { try CommunityPageParser.profile("<html>登录</html>", userID: 42, section: .music) }
    }
    @Test func csrfAndCommentOwnershipRequireVisibleControls() throws {
        let html = Self.contextHTML
        let ctx = try CommunityPageParser.discContext(html)
        #expect(ctx.userID == 42 && ctx.canComment && ctx.myComment == nil)
        #expect(ctx.csrf == "fixture-csrf")
        let withComment = html.replacingOccurrences(of: "<textarea id='comment_txt_box'></textarea>", with: "<p>自己的短评</p><button onclick='deletemycomment()'>删除</button>")
        let own = try CommunityPageParser.discContext(withComment)
        #expect(own.myComment == "自己的短评" && !own.canComment)
        let anonymous = try CommunityPageParser.discContext("<div id='commentbox'></div>")
        #expect(anonymous.userID == nil && anonymous.myComment == nil)
        #expect(try CommunityPageParser.csrf("<script>let x={'csrfmiddlewaretoken':'abc123'}</script>") == "abc123")
    }
    @Test func followUsesObservedSamePageQueryOnly() throws {
        let prefix = "<a class='dropdown-item' href='/u/42'>我</a>"
        let html = prefix + "<a href='?ilikeit'><button name='likeit-on'>关注</button></a>"
        let follow = try #require(try CommunityPageParser.follow(html))
        #expect(!follow.isFollowing && follow.query == "ilikeit" && follow.userID == 42)
        #expect(try CommunityPageParser.follow("<a href='?ilikeit'><button name='likeit-on'>关注</button></a>") == nil)
        for bad in ["https://evil.invalid/?ilikeit", "?ilikeit&extra", "?ilikeit=1", "?delete=everything"] {
            #expect(throws: DizzyError.self) { try CommunityPageParser.follow(html.replacingOccurrences(of: "?ilikeit", with: bad)) }
        }
    }
    @Test func shuffleRejectsUntrustedStreamsAndKeepsTrackNumber() throws {
        var obj: [String: Any] = ["discid":"DEMO", "thistrack":"音乐", "disctitle":"专辑", "thisurl":"https://streaming.dizzylab.net/time/sig/DEMO/preview/2.mp3", "disclabel":"社团"]
        let selection = try CommunityJSON.shuffle(JSONSerialization.data(withJSONObject: obj))
        #expect(selection.track.number == "2" && selection.track.discID == "DEMO")
        obj["thisurl"] = "https://evil.invalid/2.mp3"
        #expect(throws: DizzyError.self) { try CommunityJSON.shuffle(JSONSerialization.data(withJSONObject: obj)) }
    }
    nonisolated static let contextHTML = "<a class='dropdown-item' href='/u/42'>我</a><form id='commitbox'><input name='csrfmiddlewaretoken' value='fixture-csrf'><textarea id='comment_txt_box'></textarea></form><div id='commentbox'></div>"
}

nonisolated private final class CommunityStub: URLProtocol, @unchecked Sendable {
    nonisolated(unsafe) static var handler: (@Sendable (URLRequest) -> String)?
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        guard let handler = Self.handler, let url = request.url else { return }
        let response = HTTPURLResponse(url: url, statusCode: 200, httpVersion: nil, headerFields: nil)!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: Data(handler(request).utf8))
        client?.urlProtocolDidFinishLoading(self)
    }
    override func stopLoading() {}
}

@Suite(.serialized)
struct CommunityNetworkTests {
    private func api(_ handler: @escaping @Sendable (URLRequest) -> String) -> DizzyCommunity {
        CommunityStub.handler = handler
        let config = URLSessionConfiguration.dizzy
        config.protocolClasses = [CommunityStub.self]
        return DizzyCommunity(client: DizzyHTTPClient(session: URLSession(configuration: config)))
    }
    @Test func likeIsConfirmedByFreshReadAndNotRetried() async throws {
        let state = CommunityRequestState()
        let service = api { request in
            if request.httpMethod == "POST" {
                state.increment()
                #expect(request.url?.path == "/albums/ilikethisornot")
                #expect(request.value(forHTTPHeaderField: "Referer") == "https://www.dizzylab.net/d/DEMO/")
                return "ok"
            }
            if request.url?.path == "/albums/getthisdisclikes" { return "{\"likes\":\(state.count),\"ilikethis\":\(state.count > 0)}" }
            return CommunityTests.contextHTML
        }
        let likes = try await service.toggleLike("DEMO", userID: 42)
        #expect(likes.ilikethis && likes.likes == 1 && state.count == 1)
    }
    @Test func unchangedLikeDoesNotReportSuccessOrRepeatPost() async throws {
        let state = CommunityRequestState()
        let service = api { request in
            if request.httpMethod == "POST" { state.increment(); return "ok" }
            if request.url?.path == "/albums/getthisdisclikes" { return "{\"likes\":3,\"ilikethis\":false}" }
            return CommunityTests.contextHTML
        }
        await #expect(throws: CommunityFailure.self) { try await service.toggleLike("DEMO", userID: 42) }
        #expect(state.count == 1)
    }
    @Test func wrongAccountAndMissingOwnCommentCannotMutate() async throws {
        let state = CommunityRequestState()
        let service = api { request in
            if request.httpMethod == "POST" { state.increment() }
            if request.url?.path == "/albums/getthisdisclikes" { return "{\"likes\":0,\"ilikethis\":false}" }
            return CommunityTests.contextHTML
        }
        await #expect(throws: DizzyError.self) { try await service.toggleLike("DEMO", userID: 99) }
        await #expect(throws: CommunityFailure.self) { try await service.deleteComment(discID: "DEMO", userID: 42) }
        await #expect(throws: CommunityFailure.self) { try await service.postComment("  ", discID: "DEMO", userID: 42) }
        await #expect(throws: CommunityFailure.self) { try await service.postComment(String(repeating: "字", count: 141), discID: "DEMO", userID: 42) }
        #expect(state.count == 0)
    }
    @Test func postingVerifiesOwnCommentAndDeletionVerifiesAbsence() async throws {
        let state = CommunityRequestState()
        let own = CommunityTests.contextHTML.replacingOccurrences(of: "<textarea id='comment_txt_box'></textarea>", with: "<p>测试 &amp; 音乐</p><button onclick='deletemycomment()'>删除</button>")
        let service = api { request in
            if request.httpMethod == "POST" { state.increment(); return "ok" }
            return state.count == 1 ? own : CommunityTests.contextHTML
        }
        try await service.postComment("测试 & 音乐", discID: "DEMO", userID: 42)
        try await service.deleteComment(discID: "DEMO", userID: 42)
        #expect(state.count == 2)
    }
    @Test func followReadsActualQueryAndVerifiesResult() async throws {
        let state = CommunityRequestState()
        let service = api { request in
            if request.url?.query == "ilikeit" { state.increment() }
            return "<a class='dropdown-item' href='/u/42'>我</a><a href='?\(state.count == 0 ? "ilikeit" : "dislike")'><button name='likeit-\(state.count == 0 ? "on" : "off")'>关注</button></a>"
        }
        #expect(try await service.setFollowing(true, name: "中文 社团", userID: 42))
        #expect(try await service.setFollowing(true, name: "中文 社团", userID: 42))
        #expect(state.count == 1)
    }
}
nonisolated private final class CommunityRequestState: @unchecked Sendable {
    private let lock = NSLock()
    private var value = 0
    var count: Int { lock.lock(); defer { lock.unlock() }; return value }
    func increment() { lock.lock(); value += 1; lock.unlock() }
}
