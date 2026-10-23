import Foundation
import Testing
@testable import NeoDizzy

struct AlipayReturnRouterTests {
    private let order = "h5_route_token=\"synthetic+token/%2B&值\"&is_h5_route=\"true\"&return_url=\"https://www.dizzylab.net/return/?a=1%26b=2\"&sign=\"unchanged+/%25==\""

    private func paymentURL(scheme: String = "alipay", envelope: [String: Any]) throws -> URL {
        let data = try JSONSerialization.data(withJSONObject: envelope)
        let encoded = try #require(String(data: data, encoding: .utf8)?.addingPercentEncoding(withAllowedCharacters: .alphanumerics))
        return try #require(URL(string: "\(scheme)://alipayclient/?\(encoded)"))
    }

    private func envelope(from url: URL) throws -> [String: Any] {
        let encoded = try #require(URLComponents(url: url, resolvingAgainstBaseURL: false)?.percentEncodedQuery)
        let decoded = try #require(encoded.removingPercentEncoding?.data(using: .utf8))
        return try #require(JSONSerialization.jsonObject(with: decoded) as? [String: Any])
    }

    @Test(arguments: ["alipay", "alipays"])
    func changesOnlyOuterCallbackSchemeAndPreservesOrderExactly(_ scheme: String) throws {
        let original = try paymentURL(scheme: scheme, envelope: [
            "requestType": "SafePay", "fromAppUrlScheme": "alipays", "dataString": order,
            "additionalMetadata": ["flag": true, "text": "保持原值 + % &"],
        ])
        let result = try #require(AlipayReturnRouter.paymentURL(from: original))
        let payload = try envelope(from: result)
        #expect(result.scheme == scheme)
        #expect(result.host == "alipayclient")
        #expect(payload["requestType"] as? String == "SafePay")
        #expect(payload["fromAppUrlScheme"] as? String == "neodizzy-pay")
        #expect(payload["dataString"] as? String == order)
        #expect((payload["additionalMetadata"] as? [String: Any])?["text"] as? String == "保持原值 + % &")
        #expect((payload["additionalMetadata"] as? [String: Any])?["flag"] as? Bool == true)
    }

    @Test func rewritingAnAlreadyPreparedEnvelopeIsIdempotent() throws {
        let original = try paymentURL(envelope: [
            "requestType": "SafePay", "fromAppUrlScheme": "alipays", "dataString": order,
        ])
        let prepared = try #require(AlipayReturnRouter.paymentURL(from: original))
        #expect(AlipayReturnRouter.paymentURL(from: prepared) == prepared)
    }

    @Test func suppliesCallbackForBrowserEnvelopeWithoutSourceScheme() throws {
        let original = try paymentURL(envelope: ["requestType": "SafePay", "dataString": order])
        let result = try #require(AlipayReturnRouter.paymentURL(from: original))
        let payload = try envelope(from: result)
        #expect(payload["fromAppUrlScheme"] as? String == "neodizzy-pay")
        #expect(payload["dataString"] as? String == order)
    }

    @Test func replacesExistingRoutingMetadataWithoutReserializingOtherParameters() throws {
        let raw = "alipays://platformapi/startapp?appId=20000067&url=https%3a%2f%2fmclient.alipay.com%2f%3fsign%3da%252Bb%26return_url%3dsite&MQPSourceAppScheme=old-app&unchanged=a+b%2f%25"
        let url = try #require(URL(string: raw))
        let prepared = try #require(AlipayReturnRouter.paymentURL(from: url))
        #expect(prepared.absoluteString == raw.replacingOccurrences(of: "MQPSourceAppScheme=old-app", with: "MQPSourceAppScheme=neodizzy-pay"))
    }

    @Test func duplicateRoutingMetadataIsNotGuessed() throws {
        let url = try #require(URL(string: "alipays://platformapi/startapp?appId=20000067&MQPSourceAppScheme=a&MQPSourceAppScheme=b"))
        #expect(AlipayReturnRouter.paymentURL(from: url) == nil)
    }

    @Test(arguments: [
        "alipays://platformapi/startapp?appId=20000067&url=https%3A%2F%2Fexample.com",
        "https://mclient.alipay.com/h5pay/landing?return_url=https%3A%2F%2Fwww.dizzylab.net",
        "alipay://alipayclient/?not-json",
        "alipay://alipayclient/?%5B%5D",
        "alipay://alipayclient/?dataString=order&fromAppUrlScheme=alipays",
        "alipay://alipayclient.evil.example/",
        "neodizzy-pay://safepay/",
    ])
    func unsupportedShapesAreNotModified(_ string: String) throws {
        #expect(AlipayReturnRouter.paymentURL(from: try #require(URL(string: string))) == nil)
    }

    @Test func missingOrDifferentEnvelopeFieldsAreNotModified() throws {
        let payloads: [[String: Any]] = [
            ["requestType": "OAuth", "fromAppUrlScheme": "alipays", "dataString": order],
            ["requestType": "SafePay", "fromAppUrlScheme": NSNull(), "dataString": order],
            ["requestType": "SafePay", "fromAppUrlScheme": 12, "dataString": order],
            ["requestType": "SafePay", "fromAppUrlScheme": "alipays", "dataString": ""],
            ["requestType": "SafePay", "fromAppUrlScheme": "alipays", "dataString": ["order": order]],
        ]
        for payload in payloads {
            #expect(AlipayReturnRouter.paymentURL(from: try paymentURL(envelope: payload)) == nil)
        }
    }

    @Test func rejectsUnexpectedOriginComponentsEvenForValidEnvelope() throws {
        let valid = try paymentURL(envelope: [
            "requestType": "SafePay", "fromAppUrlScheme": "alipays", "dataString": order,
        ])
        var components = try #require(URLComponents(url: valid, resolvingAgainstBaseURL: false))
        components.user = "other"
        #expect(AlipayReturnRouter.paymentURL(from: try #require(components.url)) == nil)
        components.user = nil
        components.port = 123
        #expect(AlipayReturnRouter.paymentURL(from: try #require(components.url)) == nil)
        components.port = nil
        components.fragment = "fragment"
        #expect(AlipayReturnRouter.paymentURL(from: try #require(components.url)) == nil)
    }

    @Test(arguments: ["neodizzy-pay://safepay", "neodizzy-pay://safepay/?resultStatus=9000", "neodizzy-pay://safepay/?resultStatus=6001"])
    func callbackIsOnlyARecheckSignalRegardlessOfClaimedResult(_ string: String) throws {
        #expect(AlipayReturnRouter.isCallback(try #require(URL(string: string))))
    }

    @Test(arguments: [
        "neodizzy-pay://other", "neodizzy-pay://safepay/extra", "neodizzy-pay://safepay.evil/",
        "neodizzy-pay://user@safepay/", "neodizzy-pay://safepay:12/", "neodizzy-pay://safepay/#other",
        "https://safepay/", "alipay://safepay/",
    ])
    func unrelatedCallbacksAreIgnored(_ string: String) throws {
        #expect(!AlipayReturnRouter.isCallback(try #require(URL(string: string))))
    }
}
