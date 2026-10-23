import Foundation
import Testing
@testable import NeoDizzy

struct QQMusicLoginTests {
    private let now = Date(timeIntervalSince1970: 1_800_000_000)
    private let candidate = QQMusicCredential(musicID: "123", musicKey: "music-key", nickname: "Existing name")

    @Test func browserVisibleParentAndWebsiteCookiesCanFormOneMusicSession() throws {
        for (idName, key) in [("qqmusic_uin", "Q_H_L_session"), ("uin", "Q_H_L_session"), ("wxuin", "W_X_session")] {
            for keyName in ["qqmusic_key", "qm_keyst"] {
                for (idDomain, keyDomain) in [(".qq.com", ".y.qq.com"), (".y.qq.com", ".qq.com")] {
                    let cookies = [cookie(idName, "123", domain: idDomain), cookie(keyName, key, domain: keyDomain)]
                    let result = try QQMusicLoginClient.credential(from: cookies, now: now)
                    #expect(result.musicID == "123")
                    #expect(result.musicKey == key)
                    #expect(result.loginType == (idName == "wxuin" ? 1 : 2))
                }
            }
        }
    }

    @Test func cookiesOutsideTheFixedWebsiteURLCannotSupplyOrConflictWithLogin() throws {
        let valid = [cookie("qqmusic_uin", "123"), cookie("qqmusic_key", "Q_H_L_session")]
        for domain in ["c6.y.qq.com", ".c6.y.qq.com", "xui.ptlogin2.qq.com", "qq.com.invalid", "y.qq.com.invalid", "evily.qq.com", ".com"] {
            let unrelated = [cookie("qqmusic_uin", "456", domain: domain), cookie("qqmusic_key", "other-key", domain: domain)]
            #expect(throws: QQMusicLoginError.loginRequired) { try QQMusicLoginClient.credential(from: unrelated, now: now) }
            #expect(try QQMusicLoginClient.credential(from: valid + unrelated, now: now).musicID == "123")
        }
        for path in ["/portal", "/n/ryqq", "//"] {
            let unrelated = [cookie("qqmusic_uin", "456", path: path), cookie("qqmusic_key", "other-key", path: path)]
            #expect(throws: QQMusicLoginError.loginRequired) { try QQMusicLoginClient.credential(from: unrelated, now: now) }
            #expect(try QQMusicLoginClient.credential(from: valid + unrelated, now: now).musicID == "123")
        }
    }

    @Test func aHostOnlyParentCookieDoesNotApplyToTheMusicWebsite() throws {
        let hostOnly = HTTPCookie.cookies(withResponseHeaderFields: ["Set-Cookie": "qqmusic_uin=456; Path=/"],
                                         for: URL(string: "https://qq.com/")!)
        let parentDomain = HTTPCookie.cookies(withResponseHeaderFields: ["Set-Cookie": "qqmusic_uin=123; Domain=qq.com; Path=/"],
                                             for: URL(string: "https://y.qq.com/")!)
        let musicKey = cookie("qqmusic_key", "music-key")
        #expect(throws: QQMusicLoginError.accountIdentifierMissing) {
            try QQMusicLoginClient.credential(from: hostOnly + [musicKey], now: now)
        }
        #expect(try QQMusicLoginClient.credential(from: hostOnly + parentDomain + [musicKey], now: now).musicID == "123")
    }

    @Test func incompleteWebsiteScopeDoesNotBorrowAnAccountFromAnotherPath() throws {
        let cookies = [cookie("qqmusic_uin", "123", path: "/portal"), cookie("qqmusic_key", "music-key")]
        #expect(throws: QQMusicLoginError.accountIdentifierMissing) { try QQMusicLoginClient.credential(from: cookies, now: now) }
    }

    @Test func matchingQQAliasesAndDuplicateScopesIdentifyTheSameAccount() throws {
        let cookies = [cookie("uin", "o000123", domain: ".qq.com"), cookie("uin", "123"), cookie("qqmusic_uin", "123"),
                       cookie("qqmusic_uin", "123", domain: ".qq.com"),
                       cookie("qqmusic_key", "Q_H_L_session"), cookie("qm_keyst", "Q_H_L_session", domain: ".qq.com")]
        for input in [cookies, Array(cookies.reversed())] {
            let result = try QQMusicLoginClient.credential(from: input, now: now)
            #expect(result.musicID == "123")
            #expect(result.musicKey == "Q_H_L_session")
            #expect(result.loginType == 2)
            #expect(result.nickname == nil)
        }
    }

    @Test func wechatWebsiteCookieShapePreservesLargeIDThroughValidation() async throws {
        // Names and scopes match the observed website session; all values are
        // synthetic. This 19-digit ID exceeds Int64 and JavaScript's safe integer.
        let id = "9999999999999999999"
        let key = "W_X_synthetic-session"
        let cookies = [cookie("wxuin", id, domain: ".qq.com"), cookie("wxuin", id),
                       cookie("qqmusic_key", key, domain: ".qq.com"),
                       cookie("qm_keyst", key, domain: ".qq.com"), cookie("qm_keyst", key)]
        let fixture = LoginTransportFixture()
        let client = QQMusicLoginClient(transport: { try await fixture.send($0) })
        for input in [cookies, Array(cookies.reversed())] {
            let result = try QQMusicLoginClient.credential(from: input, now: now)
            #expect(result.musicID == id)
            #expect(result.musicKey == key)
            #expect(result.loginType == 1)
            #expect(try await client.validate(result) == result)
        }
        let request = try #require(await fixture.requests.first)
        let query = URLComponents(url: request.url!, resolvingAgainstBaseURL: false)!.queryItems!
        #expect(query.first { $0.name == "loginUin" }?.value == id)
        #expect(query.first { $0.name == "userid" }?.value == id)
        #expect(request.value(forHTTPHeaderField: "Cookie")?.contains("qqmusic_uin=\(id);") == true)
    }

    @Test func wechatMusicKeySelectsWechatIdentityInsteadOfQQSSOIdentity() throws {
        let cookies = [cookie("uin", "o000456", domain: ".qq.com"), cookie("wxuin", "9999999999999999999"),
                       cookie("uin", "o000789"),
                       cookie("qqmusic_key", "W_X_session", domain: ".qq.com"), cookie("p_skey", "sso-key", domain: ".qq.com")]
        for input in [cookies, Array(cookies.reversed())] {
            let result = try QQMusicLoginClient.credential(from: input, now: now)
            #expect(result.musicID == "9999999999999999999")
            #expect(result.loginType == 1)
        }
    }

    @Test func wechatMusicKeyMayUseMusicIdentityButNeverGenericQQUinAsFallback() throws {
        for keyName in ["qqmusic_key", "qm_keyst"] {
            let musicIdentity = [cookie("qqmusic_uin", "9999999999999999999"), cookie(keyName, "W_X_session")]
            #expect(try QQMusicLoginClient.credential(from: musicIdentity, now: now).loginType == 1)
            let qqIdentity = [cookie("uin", "123"), cookie(keyName, "W_X_session")]
            #expect(throws: QQMusicLoginError.accountIdentifierMissing) { try QQMusicLoginClient.credential(from: qqIdentity, now: now) }
        }
    }

    @Test func qqMusicKeyRequiresQQIdentityAndIgnoresUnrelatedWechatIdentity() throws {
        for key in ["Q_H_L_session", "ordinary-key", "w_x_lowercase-session"] {
            let qqCookies = [cookie("qqmusic_uin", "123"), cookie("uin", "o000123"), cookie("qqmusic_key", key)]
            let cookies = qqCookies + [cookie("wxuin", "9999999999999999999"), cookie("wxuin", "8888888888888888888", domain: ".qq.com")]
            #expect(try QQMusicLoginClient.credential(from: cookies, now: now).musicID == "123")
            #expect(throws: QQMusicLoginError.accountIdentifierMissing) {
                try QQMusicLoginClient.credential(from: [cookie("wxuin", "123"), cookie("qqmusic_key", key)], now: now)
            }
        }
    }

    @Test func differentVisibleMusicKeysAreAmbiguousAcrossNamesAndDomains() throws {
        let first = [cookie("qqmusic_uin", "123"), cookie("qqmusic_key", "Q_H_L_first")]
        for second in [cookie("qqmusic_key", "Q_H_L_second"), cookie("qm_keyst", "Q_H_L_second"),
                       cookie("qqmusic_key", "W_X_other", domain: ".qq.com"), cookie("qm_keyst", "W_X_other", domain: ".qq.com")] {
            #expect(throws: QQMusicLoginError.ambiguousCookies) { try QQMusicLoginClient.credential(from: first + [second], now: now) }
        }
    }

    @Test func conflictingVisibleAccountNamesAreRejectedInsteadOfSelectingArbitrarily() throws {
        for (idName, key) in [("qqmusic_uin", "Q_H_L_session"), ("uin", "Q_H_L_session"), ("wxuin", "W_X_session")] {
            let cookies = [cookie(idName, "123"), cookie(idName, "456", domain: ".qq.com"), cookie("qqmusic_key", key)]
            #expect(throws: QQMusicLoginError.ambiguousCookies) { try QQMusicLoginClient.credential(from: cookies, now: now) }
        }
        for (otherID, key) in [("uin", "Q_H_L_session"), ("wxuin", "W_X_session")] {
            let cookies = [cookie("qqmusic_uin", "123"), cookie(otherID, "456"), cookie("qqmusic_key", key)]
            #expect(throws: QQMusicLoginError.ambiguousCookies) { try QQMusicLoginClient.credential(from: cookies, now: now) }
        }
    }

    @Test func missingIdentityAndPendingMusicAuthorizationHaveDistinctErrors() throws {
        #expect(throws: QQMusicLoginError.loginRequired) { try QQMusicLoginClient.credential(from: [], now: now) }
        for idName in ["qqmusic_uin", "uin", "wxuin"] {
            let ssoOnly = [cookie(idName, "123", domain: ".qq.com"), cookie("p_skey", "sso-key", domain: ".qq.com"),
                           cookie("skey", "sso-key", domain: ".qq.com")]
            #expect(throws: QQMusicLoginError.musicAuthorizationPending) { try QQMusicLoginClient.credential(from: ssoOnly, now: now) }
        }
        for keyName in ["qqmusic_key", "qm_keyst"] {
            #expect(throws: QQMusicLoginError.accountIdentifierMissing) {
                try QQMusicLoginClient.credential(from: [cookie(keyName, "W_X_session")], now: now)
            }
        }
        #expect(throws: QQMusicLoginError.loginRequired) {
            try QQMusicLoginClient.credential(from: [cookie("p_skey", "sso-key"), cookie("skey", "sso-key")], now: now)
        }
    }

    @Test func expiredAndEmptyFieldsDoNotCompleteOrConflictWithTheCurrentSession() throws {
        for invalid in [cookie("qqmusic_key", "key", expires: now.addingTimeInterval(-1)),
                        cookie("qqmusic_key", "key", expires: now), cookie("qqmusic_key", "")] {
            #expect(throws: QQMusicLoginError.musicAuthorizationPending) {
                try QQMusicLoginClient.credential(from: [cookie("qqmusic_uin", "123"), invalid], now: now)
            }
        }
        let valid = [cookie("qqmusic_uin", "123"), cookie("qqmusic_key", "key", expires: now.addingTimeInterval(60))]
        let old = [cookie("qqmusic_uin", "456", expires: now), cookie("qm_keyst", "old-key", expires: now)]
        #expect(try QQMusicLoginClient.credential(from: valid + old, now: now).musicKey == "key")
    }

    @Test func invalidCookieAccountValuesAreRejected() throws {
        for idName in ["qqmusic_uin", "wxuin"] {
            for id in ["0", "-1", "o123", "abc", "18446744073709551616"] {
                #expect(throws: QQMusicLoginError.loginRequired) {
                    try QQMusicLoginClient.credential(from: [cookie(idName, id), cookie("qqmusic_key", "W_X_session")], now: now)
                }
            }
        }
    }

    @Test func validatesUsingUpstreamWebProfileContractAndExplicitMusicCookies() async throws {
        let fixture = LoginTransportFixture()
        let client = QQMusicLoginClient(transport: { try await fixture.send($0) })
        #expect(try await client.validate(candidate) == candidate)
        let requests = await fixture.requests
        let request = try #require(requests.first)
        #expect(requests.count == 1)
        #expect(request.url?.scheme == "https")
        #expect(request.url?.host == "c6.y.qq.com")
        #expect(request.url?.path == "/rsc/fcgi-bin/fcg_get_profile_homepage.fcg")
        let query = Dictionary(uniqueKeysWithValues: URLComponents(url: request.url!, resolvingAgainstBaseURL: false)!.queryItems!.map { ($0.name, $0.value!) })
        #expect(query["format"] == "json")
        #expect(query["g_tk"] == "362799932")
        #expect(query["loginUin"] == "123")
        #expect(query["userid"] == "123")
        #expect(query["hostUin"] == "0")
        #expect(query["cid"] == "205360838")
        #expect(request.value(forHTTPHeaderField: "Cookie") == "uin=123; qqmusic_uin=123; qm_keyst=music-key; qqmusic_key=music-key")
        #expect(request.value(forHTTPHeaderField: "Referer") == "https://y.qq.com/")
        #expect(request.httpShouldHandleCookies == false)
    }

    @Test func invalidAccountOrUnsafeCredentialCannotEnterAnHTTPHeader() async throws {
        let fixture = LoginTransportFixture()
        let client = QQMusicLoginClient(transport: { try await fixture.send($0) })
        let invalidIDs = ["", "0", "-1", "o123", "abc", "12;other=123", "１２３"]
        let invalidKeys = ["", "key;uin=456", "key\r\nX-Test: injected", "key with space", "key\"quoted", "key,other", "key\\other"]
        let candidates = invalidIDs.map { QQMusicCredential(musicID: $0, musicKey: "key") }
            + invalidKeys.map { QQMusicCredential(musicID: "123", musicKey: $0) }
        for candidate in candidates {
            await #expect(throws: QQMusicLoginError.loginRequired) { try await client.validate(candidate) }
        }
        #expect(await fixture.requests.isEmpty)
    }

    @Test func nonzeroStatusAndMalformedResponsesDoNotValidate() async throws {
        for code in [1000, 104401] {
            let json = "{\"code\":\(code)}"
            let client = QQMusicLoginClient(transport: { request in
                (Data(json.utf8), Self.response(request))
            })
            await #expect(throws: QQMusicLoginError.server(code)) { try await client.validate(candidate) }
        }
        for json in ["<html>failure</html>", #"{}"#, #"{"code":false}"#, #"{"code":"0"}"#] {
            let client = QQMusicLoginClient(transport: { request in (Data(json.utf8), Self.response(request)) })
            await #expect(throws: QQMusicLoginError.invalidResponse) { try await client.validate(candidate) }
        }
    }

    @Test func httpRedirectAndUnexpectedResponseDomainAreRejected() async throws {
        let redirect = LoginTransportFixture(status: 302)
        let client = QQMusicLoginClient(transport: { try await redirect.send($0) })
        await #expect(throws: QQMusicLoginError.http(302)) { try await client.validate(candidate) }
        #expect(await redirect.requests.count == 1)
        let unexpected = QQMusicLoginClient(transport: { _ in
            (Data(#"{"code":0}"#.utf8), HTTPURLResponse(url: URL(string: "https://example.com/")!, statusCode: 200, httpVersion: nil, headerFields: nil)!)
        })
        await #expect(throws: QQMusicLoginError.invalidResponse) { try await unexpected.validate(candidate) }
    }

    @Test func transportFailureDoesNotBecomeSuccessfulLogin() async throws {
        let client = QQMusicLoginClient(transport: { _ in throw URLError(.notConnectedToInternet) })
        await #expect(throws: URLError.self) { try await client.validate(candidate) }
    }

    @Test func disabledModuleDoesNotStartValidationAndCanBeReenabled() async throws {
        let fixture = LoginTransportFixture()
        let client = QQMusicLoginClient(transport: { try await fixture.send($0) })
        await client.setEnabled(false)
        await #expect(throws: CancellationError.self) { try await client.validate(candidate) }
        #expect(await fixture.requests.isEmpty)
        await client.setEnabled(true)
        #expect(try await client.validate(candidate) == candidate)
    }

    @Test func disableAndCancelRejectLateValidationEvenWhenTransportIgnoresCancellation() async throws {
        for disable in [false, true] {
            let gate = LoginResponseGate()
            let client = QQMusicLoginClient(transport: { request in
                await gate.wait()
                return (Data(#"{"code":0}"#.utf8), Self.response(request))
            })
            let work = Task { try await client.validate(candidate) }
            await gate.waitForStart()
            if disable { await client.setEnabled(false) } else { await client.cancel() }
            await gate.release()
            await #expect(throws: CancellationError.self) { try await work.value }
        }
    }

    @Test func callerTaskCancellationRejectsLateValidation() async throws {
        let gate = LoginResponseGate()
        let client = QQMusicLoginClient(transport: { request in
            await gate.wait()
            return (Data(#"{"code":0}"#.utf8), Self.response(request))
        })
        let work = Task { try await client.validate(candidate) }
        await gate.waitForStart()
        work.cancel()
        await gate.release()
        await #expect(throws: CancellationError.self) { try await work.value }
    }

    @Test func newerValidationInvalidatesTheOlderAccountResult() async throws {
        let gate = LoginResponseGate()
        let client = QQMusicLoginClient(transport: { request in
            if request.value(forHTTPHeaderField: "Cookie")?.contains("music-key") == true { await gate.wait() }
            return (Data(#"{"code":0}"#.utf8), Self.response(request))
        })
        let first = Task { try await client.validate(candidate) }
        await gate.waitForStart()
        let second = QQMusicCredential(musicID: "456", musicKey: "second-key")
        #expect(try await client.validate(second) == second)
        await gate.release()
        await #expect(throws: CancellationError.self) { try await first.value }
    }

    private func cookie(_ name: String, _ value: String, domain: String = ".y.qq.com", path: String = "/", expires: Date? = nil) -> HTTPCookie {
        var properties: [HTTPCookiePropertyKey: Any] = [.name: name, .value: value, .domain: domain, .path: path, .secure: "TRUE"]
        if let expires { properties[.expires] = expires }
        return HTTPCookie(properties: properties)!
    }

    nonisolated private static func response(_ request: URLRequest) -> HTTPURLResponse {
        HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!
    }
}

private actor LoginTransportFixture {
    private let status: Int
    var requests: [URLRequest] = []
    init(status: Int = 200) { self.status = status }
    func send(_ request: URLRequest) throws -> (Data, HTTPURLResponse) {
        requests.append(request)
        return (Data(#"{"code":0}"#.utf8), HTTPURLResponse(url: request.url!, statusCode: status, httpVersion: nil, headerFields: ["Location": "https://example.com/"])!)
    }
}

private actor LoginResponseGate {
    private var response: CheckedContinuation<Void, Never>?
    private var started: CheckedContinuation<Void, Never>?
    func wait() async {
        await withCheckedContinuation { continuation in
            response = continuation
            started?.resume()
            started = nil
        }
    }
    func waitForStart() async {
        if response != nil { return }
        await withCheckedContinuation { started = $0 }
    }
    func release() { response?.resume(); response = nil }
}
