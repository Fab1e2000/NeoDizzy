// Adapted from MeloX NeteaseDirectClient.swift (GPL-3.0), commit
// 1fe5fbab3f554e8529c4847fc54281a472b7b61a. Uses its eapi framing and AES-ECB transport.
import CommonCrypto
import CryptoKit
import Foundation
import Security

nonisolated enum NeteaseError: LocalizedError {
    case encoding, response, emptyResponse, loginRequired, unavailable
    case checkTokenUnavailable
    case server(Int)
    case httpStatus(Int)
    case rejected(Int, String)
    var errorDescription: String? {
        switch self {
        case .checkTokenUnavailable: "网易云操作校验暂不可用，请稍后再试；未提交收藏请求"
        case .encoding: "无法生成网易云请求"
        case .emptyResponse: "网易云暂未返回数据，请重试"
        case .response: "网易云返回了无法识别的数据，请稍后重试"
        case .loginRequired: "请先登录网易云音乐，或重新登录已失效的账号"
        case .unavailable: "此歌曲暂无可用音源，可能需要会员、购买或在官方客户端收听"
        case .server(let code): "网易云请求失败（\(code)），请稍后重试"
        case .httpStatus(let code): "网易云网络请求失败（HTTP \(code)）"
        case .rejected(let code, let message): "网易云返回 \(code)：\(message)"
        }
    }
}

@MainActor
final class NeteaseClient {
    var cookie = "" { didSet { if oldValue != cookie { generation += 1 } } }
    private var generation = 0
    private let session: URLSession
    private let deviceID: String
    private let checkTokenProvider: @MainActor () async throws -> String

    init(session: URLSession? = nil, defaults: UserDefaults = .standard,
         checkTokenProvider: @escaping @MainActor () async throws -> String = { try await NeteaseCheckToken().fetch() }) {
        self.checkTokenProvider = checkTokenProvider
        let configuration = URLSessionConfiguration.ephemeral
        configuration.httpMaximumConnectionsPerHost = 4
        configuration.httpCookieStorage = nil
        configuration.httpShouldSetCookies = false
        self.session = session ?? URLSession(configuration: configuration)
        let key = "netease.deviceID"
        deviceID = defaults.string(forKey: key) ?? UUID().uuidString.replacingOccurrences(of: "-", with: "")
        defaults.set(deviceID, forKey: key)
    }

    func request<Response: Decodable>(_ path: String, data: [String: Any] = [:], authenticated: Bool = false,
                                      requiresCheckToken: Bool = false, acceptedCodes: Set<Int> = [200], clientLog: Bool = false) async throws -> Response {
        let revision = generation
        if authenticated && Self.cookieValues(cookie)["MUSIC_U"] == nil { throw NeteaseError.loginRequired }
        let token = requiresCheckToken ? try await checkTokenProvider() : nil
        try Task.checkCancellation()
        guard revision == generation else { throw CancellationError() }
        if requiresCheckToken && (token?.isEmpty != false) { throw NeteaseError.checkTokenUnavailable }
        return try await send(makeRequest(path, data: data, authenticated: authenticated, checkToken: token, clientLog: clientLog), acceptedCodes: acceptedCodes)
    }

    private func send<Response: Decodable>(_ request: URLRequest, acceptedCodes: Set<Int> = [200]) async throws -> Response {
        let revision = generation
        let (data, response) = try await session.data(for: request)
        try Task.checkCancellation()
        guard revision == generation else { throw CancellationError() }
        guard let http = response as? HTTPURLResponse else { throw NeteaseError.response }
        if http.statusCode == 401 { throw NeteaseError.loginRequired }
        guard (200..<300).contains(http.statusCode) else { throw NeteaseError.httpStatus(http.statusCode) }
        guard !data.isEmpty else { throw NeteaseError.emptyResponse }
        if let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any], let code = object["code"] as? Int, !acceptedCodes.contains(code) {
            if code == 301 || code == 401 { throw NeteaseError.loginRequired }
            let message = (object["message"] as? String) ?? (object["msg"] as? String)
            if let message, !message.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                throw NeteaseError.rejected(code, message)
            }
            throw NeteaseError.server(code)
        }
        do { return try JSONDecoder().decode(Response.self, from: data) }
        catch { throw NeteaseError.response }
    }

    /// Original WEAPI transport, with the same empty-response EAPI fallback used by MeloX.
    /// Only reads opt into fallback: an ambiguous write must never be repeated automatically.
    func webRequest<Response: Decodable>(_ path: String, data: [String: Any] = [:], authenticated: Bool = false,
                                         readFallback: Bool = false) async throws -> Response {
        do { return try await send(makeWebRequest(path, data: data, authenticated: authenticated)) }
        catch NeteaseError.emptyResponse where readFallback {
            return try await request(path, data: data, authenticated: authenticated)
        }
    }

    func makeWebRequest(_ path: String, data: [String: Any], authenticated: Bool) throws -> URLRequest {
        guard path.hasPrefix("/api/"), !path.contains("?"), !path.contains("#"),
              let url = URL(string: "https://music.163.com" + path.replacingOccurrences(of: "/api/", with: "/weapi/")) else { throw NeteaseError.encoding }
        let saved = Self.cookieValues(cookie)
        if authenticated && saved["MUSIC_U"] == nil { throw NeteaseError.loginRequired }
        var payload = data
        payload["csrf_token"] = saved["__csrf"] ?? ""
        let json = try JSONSerialization.data(withJSONObject: payload, options: [.sortedKeys])
        let secret = makeWeapiSecretKey()
        let first = try aesCBC(json, key: "0CoJUm6Qyw8W8jud").base64EncodedString()
        let params = try aesCBC(Data(first.utf8), key: secret).base64EncodedString()
        let encryptedKey = try rsaEncryptWeapiSecret(secret)
        let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "-._~"))
        var request = URLRequest(url: url)
        request.httpMethod = "POST"; request.timeoutInterval = 20; request.httpShouldHandleCookies = false
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        request.setValue("https://music.163.com", forHTTPHeaderField: "Referer")
        request.setValue("Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/124.0.0.0 Safari/537.36", forHTTPHeaderField: "User-Agent")
        var cookies = saved.filter { ["MUSIC_U", "__csrf"].contains($0.key) }
        cookies.merge(["os": "ios", "appver": "9.0.90", "osver": "16.2", "channel": "distribution", "deviceId": deviceID,
                       "__remember_me": "true", "ntes_kaola_ad": "1", "_ntes_nuid": deviceID,
                       "_ntes_nnid": "\(deviceID),\(Int(Date().timeIntervalSince1970 * 1000))", "WEVNSM": "1.0.0",
                       "WNMCID": "\(deviceID.prefix(6)).\(Int(Date().timeIntervalSince1970 * 1000)).01.0", "NMTID": UUID().uuidString.replacingOccurrences(of: "-", with: "")]) { first, _ in first }
        request.setValue(cookies.keys.sorted().map { "\($0)=\(cookies[$0]!.addingPercentEncoding(withAllowedCharacters: allowed) ?? "")" }.joined(separator: "; "), forHTTPHeaderField: "Cookie")
        request.httpBody = Data("params=\(params.addingPercentEncoding(withAllowedCharacters: allowed) ?? "")&encSecKey=\(encryptedKey)".utf8)
        return request
    }

    func makeRequest(_ path: String, data: [String: Any], authenticated: Bool, checkToken: String? = nil, clientLog: Bool = false) throws -> URLRequest {
        let domain = clientLog ? "https://clientlog.music.163.com" : "https://interface.music.163.com"
        guard path.hasPrefix("/api/"), !path.contains("?"), !path.contains("#"),
              let url = URL(string: domain + path.replacingOccurrences(of: "/api/", with: "/eapi/")) else { throw NeteaseError.encoding }
        let cookies = Self.cookieValues(cookie)
        if authenticated && cookies["MUSIC_U"] == nil { throw NeteaseError.loginRequired }
        var header = ["os": "ios", "appver": "9.0.90", "osver": "16.2", "channel": "distribution",
                      "deviceId": deviceID, "__csrf": cookies["__csrf"] ?? "",
                      "buildver": String(Int(Date().timeIntervalSince1970)),
                      "requestId": "\(Int64(Date().timeIntervalSince1970 * 1000))_\(Int.random(in: 1000...9999))"]
        if authenticated {
            // Match MeloX's authenticated EAPI profile. Website login cookies do not
            // carry a mobile profile; forcing an iOS header changes the write request identity.
            let profile = Self.authenticatedProfile(os: cookies["os"])
            header.merge([
                "os": profile.os, "appver": profile.appver, "osver": profile.osver,
                "channel": profile.channel, "versioncode": "140", "mobilename": "",
                "resolution": "1920x1080"
            ]) { _, value in value }
            for key in ["os", "appver", "osver", "channel", "versioncode", "mobilename", "resolution", "deviceId", "buildver"] {
                if let value = cookies[key], !value.isEmpty { header[key] = value }
            }
        }
        if clientLog { header["os"] = "osx" }
        if let token = cookies["MUSIC_U"] { header["MUSIC_U"] = token }
        if let checkToken { header["X-antiCheatToken"] = checkToken }
        var payload = data
        payload["header"] = header
        payload["e_r"] = false
        let jsonData = try JSONSerialization.data(withJSONObject: payload, options: [.sortedKeys])
        guard let json = String(data: jsonData, encoding: .utf8) else { throw NeteaseError.encoding }
        let digest = Insecure.MD5.hash(data: Data("nobody\(path)use\(json)md5forencrypt".utf8)).map { String(format: "%02x", $0) }.joined()
        let encrypted = try Self.encrypt(Data("\(path)-36cd479b6b5-\(json)-36cd479b6b5-\(digest)".utf8))
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.timeoutInterval = 20
        request.httpShouldHandleCookies = false
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        request.setValue("NeteaseMusic 9.0.90/5038 (iPhone; iOS 16.2; zh_CN)", forHTTPHeaderField: "User-Agent")
        request.setValue("https://music.163.com/", forHTTPHeaderField: "Referer")
        request.setValue(header.keys.sorted().map { "\($0)=\(header[$0]!.addingPercentEncoding(withAllowedCharacters: .alphanumerics.union(CharacterSet(charactersIn: "-._~"))) ?? "")" }.joined(separator: "; "), forHTTPHeaderField: "Cookie")
        request.httpBody = Data(("params=" + encrypted.map { String(format: "%02X", $0) }.joined()).utf8)
        return request
    }

    private static func authenticatedProfile(os: String?) -> (os: String, appver: String, osver: String, channel: String) {
        switch os {
        case "linux": ("linux", "1.2.1.0428", "Deepin 20.9", "netease")
        case "android": ("android", "8.20.20.231215173437", "14", "xiaomi")
        case "iphone": ("iPhone OS", "9.0.90", "16.2", "distribution")
        default: ("pc", "3.1.17.204416", "Microsoft-Windows-10-Professional-build-19045-64bit", "netease")
        }
    }

    static func cookieValues(_ value: String) -> [String: String] {
        value.split(separator: ";").reduce(into: [:]) { result, pair in
            let parts = pair.split(separator: "=", maxSplits: 1).map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            if parts.count == 2, !parts[1].isEmpty { result[parts[0]] = parts[1] }
        }
    }

    private static func encrypt(_ data: Data) throws -> Data {
        let key = "e82ckenh8dichen8"
        var output = Data(count: data.count + kCCBlockSizeAES128)
        let capacity = output.count
        var length = 0
        let status = output.withUnsafeMutableBytes { destination in
            data.withUnsafeBytes { source in
                key.withCString { key in
                    CCCrypt(CCOperation(kCCEncrypt), CCAlgorithm(kCCAlgorithmAES),
                            CCOptions(kCCOptionPKCS7Padding | kCCOptionECBMode), key, kCCKeySizeAES128, nil,
                            source.baseAddress, data.count, destination.baseAddress, capacity, &length)
                }
            }
        }
        guard status == kCCSuccess else { throw NeteaseError.encoding }
        output.removeSubrange(length..<output.count)
        return output
    }

    // Cryptographic framing adapted from MeloX NeteaseDirectClient (GPL-3.0).
    private func aesCBC(_ data: Data, key: String) throws -> Data {
        let iv = "0102030405060708"
        var output = Data(count: data.count + kCCBlockSizeAES128)
        let outputCapacity = output.count
        var outputLength = 0
        let status = output.withUnsafeMutableBytes { outputBytes in
            data.withUnsafeBytes { dataBytes in
                key.withCString { keyBytes in
                    iv.withCString { ivBytes in
                        CCCrypt(
                            CCOperation(kCCEncrypt),
                            CCAlgorithm(kCCAlgorithmAES),
                            CCOptions(kCCOptionPKCS7Padding),
                            keyBytes,
                            kCCKeySizeAES128,
                            ivBytes,
                            dataBytes.baseAddress,
                            data.count,
                            outputBytes.baseAddress,
                            outputCapacity,
                            &outputLength
                        )
                    }
                }
            }
        }
        guard status == kCCSuccess else {
            throw NeteaseError.encoding
        }
        output.removeSubrange(outputLength..<output.count)
        return output
    }

    private func makeWeapiSecretKey() -> String {
        let characters = Array("abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789")
        var generator = SystemRandomNumberGenerator()
        return String((0..<16).compactMap { _ in
            characters.randomElement(using: &generator)
        })
    }

    private func rsaEncryptWeapiSecret(_ secret: String) throws -> String {
        guard let subjectPublicKeyInfo = Data(base64Encoded: Self.weapiPublicKey),
              subjectPublicKeyInfo.count > 22 else {
            throw NeteaseError.encoding
        }
        let pkcs1Key = subjectPublicKeyInfo.dropFirst(22)
        let attributes: [CFString: Any] = [
            kSecAttrKeyType: kSecAttrKeyTypeRSA,
            kSecAttrKeyClass: kSecAttrKeyClassPublic,
            kSecAttrKeySizeInBits: 1_024,
        ]
        var keyError: Unmanaged<CFError>?
        guard let publicKey = SecKeyCreateWithData(
            Data(pkcs1Key) as CFData,
            attributes as CFDictionary,
            &keyError
        ) else {
            if let error = keyError?.takeRetainedValue() {
                throw error
            }
            throw NeteaseError.encoding
        }

        let message = Data(String(secret.reversed()).utf8)
        let blockSize = SecKeyGetBlockSize(publicKey)
        guard message.count <= blockSize else { throw NeteaseError.encoding }
        var paddedMessage = Data(repeating: 0, count: blockSize)
        paddedMessage.replaceSubrange(
            (blockSize - message.count)..<blockSize,
            with: message
        )

        var encryptionError: Unmanaged<CFError>?
        guard let encrypted = SecKeyCreateEncryptedData(
            publicKey,
            .rsaEncryptionRaw,
            paddedMessage as CFData,
            &encryptionError
        ) as Data? else {
            if let error = encryptionError?.takeRetainedValue() {
                throw error
            }
            throw NeteaseError.encoding
        }
        return encrypted.map { String(format: "%02x", $0) }.joined()
    }

    private static let weapiPublicKey = "MIGfMA0GCSqGSIb3DQEBAQUAA4GNADCBiQKBgQDgtQn2JZ34ZC28NWYpAUd98iZ37BUrX/aKzmFbt7clFSs6sXqHauqKWqdtLkF2KexO40H1YTX8z2lSgBBOAxLsvaklV8k4cBFK9snQXE9/DDaFt6Rr7iVZMldczhC0JNgTz+SHXT6CBHuX3e9SdB1Ua44oncaTWz7OBGLbCiK45wIDAQAB"

    static let checkToken = "9ca17ae2e6ffcda170e2e6ee8af14fbabdb988f225b3868eb2c15a879b9a83d274a790ac8ff54a97b889d5d42af0feaec3b92af58cff99c470a7eafd88f75e839a9ea7c14e909da883e83fb692a3abdb6b92adee9e"
}
