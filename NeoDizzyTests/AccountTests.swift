import Foundation
import Testing
@testable import NeoDizzy

struct AccountParserTests {
    @Test func loginPageHasCSRFToken() throws {
        let html = try Fixture.text("login.html")
        #expect(try LoginPageParser.csrfToken(html) == "TESTcsrfTokenValue0123456789abcdefghijklmnopqrstuvwxyzABCDEFGHIJ")
        #expect(LoginPageParser.isLoginForm(html))
        #expect(LoginPageParser.errorMessage(html) == nil)
    }

    /// 实测拿到的文字是「抱歉！登录信息错误 ×」，末尾是提示框的关闭按钮。
    /// 这里的 HTML 按 Bootstrap 4 提示框的标准写法构造。
    @Test func loginErrorMessageDropsCloseButton() {
        let html = """
        <html><body><div class="alert alert-danger alert-dismissible fade show" role="alert">抱歉！登录信息错误
        <button type="button" class="close" data-dismiss="alert" aria-label="Close"><span aria-hidden="true">&times;</span></button>
        </div><form method="post"><input name="password"></form></body></html>
        """
        #expect(LoginPageParser.errorMessage(html) == "抱歉！登录信息错误")
    }

    @Test func loggedInHomeGivesUserIDAndAvatar() throws {
        let result = try #require(try LoggedInHomeParser.parse(Fixture.text("home-loggedin.html")))
        #expect(result.userID == 1)
        #expect(result.avatarURL?.absoluteString == "https://cdn.dizzylab.net/media/avatars/1.jpg!labellittle")
    }

    @Test func anonymousHomeHasNoUser() throws {
        #expect(try LoggedInHomeParser.parse(Fixture.text("home.html")) == nil)
    }

    @Test func purchasesPageHasProfileTokenAndDiscs() throws {
        let result = try ProfileMusicPageParser.parse(Fixture.text("music.html"))
        #expect(result.nickname == "测试用户")
        #expect(result.avatarURL?.absoluteString == "https://cdn.dizzylab.net/media/avatars/1.jpg")
        #expect(result.token == "0123456789abcdef0123456789abcdef01234567")
        #expect(result.purchases.hasMore)

        let discs = result.purchases.items
        #expect(discs.map(\.id) == ["fx4", "HLRVOL4"])
        #expect(discs[0].disc.title == "Glassy Tears 44.1kHz")
        #expect(discs[0].disc.labelName == "Flexible X")
        #expect(discs[0].disc.coverURL?.absoluteString == "https://cdn.dizzylab.net/media/cover/fx4.jpg!cover")
        #expect(discs[0].purchaseDate == "2026-06-30")
        #expect(discs.allSatisfy { $0.disc.isOwned })
        #expect(!discs[0].disc.isHiRes)
        #expect(discs[1].disc.isHiRes)
    }

    @Test func pageWithoutTokenScriptHasNoToken() {
        #expect(ProfileMusicPageParser.token(in: "<script>var sort = 'ad';</script>") == nil)
    }

    @Test func feedGroupsDecode() throws {
        let response = try JSONDecoder().decode(FeedResponse.self, from: Fixture.data("getfeed.json"))
        #expect(response.canshowmore)
        let groups = response.labels.map(\.group)
        #expect(groups.map(\.labelName) == ["Flexible X", "obscuRE TRAX"])
        #expect(groups[1].discs.map(\.id) == ["obs-CD06BP", "obs-CD06B"])
        #expect(groups[1].discs[0].price == .price(45))
        #expect(groups[1].discs[0].labelName == "obscuRE TRAX")
        #expect(groups[0].discs[0].price == .free)
    }
}

struct CredentialsTests {
    private let site = URL(string: "https://www.dizzylab.net/albums/login/")!

    @Test func storesCookiesAndBuildsHeader() {
        let credentials = DizzyCredentials()
        credentials.store(HTTPCookie.cookies(withResponseHeaderFields: ["Set-Cookie": "csrftoken=abc; Path=/"], for: site))
        credentials.store(HTTPCookie.cookies(withResponseHeaderFields: ["Set-Cookie": "sessionid=xyz; HttpOnly; Path=/"], for: site))
        #expect(credentials.hasCookie(named: "sessionid"))
        #expect(credentials.cookieHeader() == "csrftoken=abc; sessionid=xyz")
    }

    /// 网站退出登录时用一个已过期的同名 Cookie 清掉 sessionid。
    @Test func expiredCookieRemovesTheOldOne() {
        let credentials = DizzyCredentials()
        credentials.store(HTTPCookie.cookies(withResponseHeaderFields: ["Set-Cookie": "sessionid=xyz; Path=/"], for: site))
        credentials.store(HTTPCookie.cookies(
            withResponseHeaderFields: ["Set-Cookie": "sessionid=\"\"; expires=Thu, 01 Jan 1970 00:00:00 GMT; Max-Age=0; Path=/"],
            for: site
        ))
        #expect(!credentials.hasCookie(named: "sessionid"))
        #expect(credentials.cookieHeader() == nil)
    }

    @Test func snapshotRoundTrips() throws {
        let credentials = DizzyCredentials()
        credentials.store(HTTPCookie.cookies(withResponseHeaderFields: ["Set-Cookie": "sessionid=xyz; Path=/"], for: site))
        credentials.setToken("0123456789abcdef0123456789abcdef01234567")
        let data = try JSONEncoder().encode(credentials.snapshot)

        let restored = DizzyCredentials()
        restored.restore(try JSONDecoder().decode(DizzyCredentials.Snapshot.self, from: data))
        #expect(restored.token == "0123456789abcdef0123456789abcdef01234567")
        #expect(restored.cookieHeader() == "sessionid=xyz")
    }

    @Test func tokenIsRedactedInLogs() {
        let url = URL(string: "https://www.dizzylab.net/apis/getfeed/?l=0&r=6&token=0123456789abcdef0123456789abcdef01234567")
        #expect(DizzyHTTPClient.redacted(url) == "https://www.dizzylab.net/apis/getfeed/?l=0&r=6&token=<token>")
    }
}

// MARK: - 模拟网站

/// 拦截请求，按路径返回样本。回调在后台线程执行，所以用 @Sendable 闭包和线程安全的记录器。
nonisolated private final class StubURLProtocol: URLProtocol, @unchecked Sendable {
    struct Reply: Sendable {
        var status = 200
        var headers: [String: String] = [:]
        var body = Data()
    }

    nonisolated(unsafe) static var handler: (@Sendable (URLRequest) -> Reply)?

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        guard let handler = Self.handler, let url = request.url else {
            client?.urlProtocol(self, didFailWithError: URLError(.badURL))
            return
        }
        let reply = handler(request)
        let response = HTTPURLResponse(url: url, statusCode: reply.status, httpVersion: "HTTP/1.1", headerFields: reply.headers)!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: reply.body)
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}
}

/// 记下模拟网站收到的请求。
nonisolated private final class RequestLog: @unchecked Sendable {
    private let lock = NSLock()
    private var entries: [(url: String, cookie: String?, body: String)] = []

    func record(_ request: URLRequest) {
        var body = ""
        if let stream = request.httpBodyStream {
            stream.open()
            var buffer = [UInt8](repeating: 0, count: 4096)
            while stream.hasBytesAvailable {
                let count = stream.read(&buffer, maxLength: buffer.count)
                guard count > 0 else { break }
                body += String(decoding: buffer[..<count], as: UTF8.self)
            }
            stream.close()
        }
        lock.withLock {
            entries.append((request.url?.absoluteString ?? "", request.value(forHTTPHeaderField: "Cookie"), body))
        }
    }

    var all: [(url: String, cookie: String?, body: String)] {
        lock.withLock { entries }
    }
}

private func html(_ text: String) -> Data {
    Data("<html><head><title>dizzylab</title></head><body>\(text)</body></html>".utf8)
}

/// 共用一个模拟网站，必须依次执行。
@Suite(.serialized)
struct AccountNetworkTests {
    private func client(_ handler: @escaping @Sendable (URLRequest) -> StubURLProtocol.Reply) -> DizzyHTTPClient {
        StubURLProtocol.handler = handler
        let configuration = URLSessionConfiguration.dizzy
        configuration.protocolClasses = [StubURLProtocol.self]
        return DizzyHTTPClient(session: URLSession(configuration: configuration))
    }

    @Test func loginStoresSessionAndToken() async throws {
        let loginPage = try Fixture.data("login.html")
        let home = try Fixture.data("home-loggedin.html")
        let music = try Fixture.data("music.html")
        let log = RequestLog()
        let client = client { request in
            log.record(request)
            // `URL.path` 会去掉末尾的 `/`，这里要保留原样。
            switch (request.httpMethod ?? "GET", request.url?.path(percentEncoded: true) ?? "") {
            case ("GET", "/albums/login/"):
                return .init(headers: ["Set-Cookie": "csrftoken=csrf-cookie; Path=/"], body: loginPage)
            case ("POST", "/albums/login/"):
                return .init(headers: ["Set-Cookie": "sessionid=session-cookie; HttpOnly; Path=/"], body: html(""))
            case ("GET", "/"):
                return .init(body: home)
            case ("GET", "/u/1/music/"):
                return .init(body: music)
            default:
                return .init(status: 404)
            }
        }

        let account = try await DizzyAuth(client: client).login(username: "tester", password: "p@ss word&=")
        #expect(account == Account(userID: 1, nickname: "测试用户", avatarURL: URL(string: "https://cdn.dizzylab.net/media/avatars/1.jpg")))
        #expect(client.credentials.token == "0123456789abcdef0123456789abcdef01234567")
        #expect(client.credentials.hasCookie(named: "sessionid"))

        let post = try #require(log.all.first { $0.body.contains("username=") })
        #expect(post.cookie == "csrftoken=csrf-cookie")
        #expect(post.body.contains("csrfmiddlewaretoken=TESTcsrfTokenValue"))
        // 密码里的 @、空格、&、= 都要转义，否则表单会被拆错。
        #expect(post.body.contains("password=p%40ss%20word%26%3D"))
        // 登录之后的请求带上会话 Cookie。
        let profile = try #require(log.all.last)
        #expect(profile.url.hasSuffix("/u/1/music/"))
        #expect(profile.cookie?.contains("sessionid=session-cookie") == true)
    }

    @Test func wrongPasswordShowsSiteMessageAndLeavesNoSession() async throws {
        let loginPage = try Fixture.data("login.html")
        let client = client { request in
            if request.httpMethod == "POST" {
                return .init(body: html("<div class=\"alert alert-danger\">用户名或密码错误</div><form method=\"post\"><input name=\"password\"></form>"))
            }
            return .init(headers: ["Set-Cookie": "csrftoken=csrf-cookie; Path=/"], body: loginPage)
        }
        await #expect(throws: DizzyError.loginFailed("用户名或密码错误")) {
            try await DizzyAuth(client: client).login(username: "tester", password: "wrong")
        }
        #expect(client.credentials.snapshot == DizzyCredentials.Snapshot())
    }

    @Test func rejectedTokenFallsBackToAnonymousDetail() async throws {
        let detail = try Fixture.data("getthisdicsinfo.json")
        let client = client { request in
            if request.url?.query?.contains("token=") == true {
                return .init(body: html("出错了！"))
            }
            return .init(body: detail)
        }
        client.credentials.setToken("dead00000000000000000000000000000000beef")
        let result = try await DizzyAPI(client: client).discDetail(id: "fx4")
        #expect(result.summary.id == "fx4")
        #expect(client.credentials.token == nil)
    }

    @Test func feedNeedsLogin() async {
        let client = client { _ in .init(status: 500) }
        await #expect(throws: DizzyError.notLoggedIn) {
            try await DizzyAPI(client: client).feed(page: 1)
        }
    }

    @Test func feedLoadsWithTokenAndReportsRejection() async throws {
        let feed = try Fixture.data("getfeed.json")
        let log = RequestLog()
        let client = client { request in
            log.record(request)
            let valid = request.url?.query?.contains("token=0123456789abcdef0123456789abcdef01234567") == true
            return .init(body: valid ? feed : html("出错了！"))
        }
        client.credentials.setToken("0123456789abcdef0123456789abcdef01234567")
        let page = try await DizzyAPI(client: client).feed(page: 2)
        #expect(page.items.count == 2)
        #expect(page.hasMore)
        #expect(log.all.last?.url.contains("l=6&r=12") == true)

        client.credentials.setToken("dead00000000000000000000000000000000beef")
        await #expect(throws: DizzyError.sessionExpired) {
            try await DizzyAPI(client: client).feed(page: 1)
        }
        #expect(client.credentials.token == nil)
    }

    @Test func cookiesAreNotSentToCDN() async throws {
        let log = RequestLog()
        let client = client { request in
            log.record(request)
            return .init(headers: ["Content-Length": "481115"])
        }
        client.credentials.store(HTTPCookie.cookies(
            withResponseHeaderFields: ["Set-Cookie": "sessionid=session-cookie; Path=/"],
            for: URL(string: "https://www.dizzylab.net/")!
        ))
        _ = try await client.contentLength(of: URL(string: "https://streaming.dizzylab.net/202609261738/abc/fx4/preview/1.mp3")!)
        #expect(log.all.last?.cookie == nil)
    }
}
