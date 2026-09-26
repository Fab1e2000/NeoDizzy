import Foundation

/// Resolves response headers without buffering or downloading the ZIP body.
nonisolated final class DownloadLinkResolver: NSObject, URLSessionTaskDelegate, @unchecked Sendable {
    private let cookie: String?

    init(cookie: String?) { self.cookie = cookie }

    static func resolve(_ url: URL, credentials: DizzyCredentials,
                        configuration: URLSessionConfiguration = .ephemeral) async throws -> URL {
        guard isSecure(url) else { throw DownloadFailure.invalidResponse }
        let delegate = DownloadLinkResolver(cookie: credentials.cookieHeader())
        configuration.httpCookieStorage = nil
        configuration.httpShouldSetCookies = false
        configuration.urlCredentialStorage = nil
        configuration.timeoutIntervalForRequest = 30
        configuration.timeoutIntervalForResource = 45
        let session = URLSession(configuration: configuration, delegate: delegate, delegateQueue: nil)
        defer { session.invalidateAndCancel() }
        // bytes(for:) returns once response headers arrive. Do not iterate the body.
        let (_, result) = try await session.bytes(for: delegate.request(for: url))
        try Task.checkCancellation()
        guard let response = result as? HTTPURLResponse, (200..<300).contains(response.statusCode),
              !isErrorContentType(response.mimeType),
              let finalURL = response.url, isSecure(finalURL) else { throw DownloadFailure.invalidResponse }
        return finalURL
    }

    static func isSecure(_ url: URL) -> Bool {
        url.scheme == "https" && url.host != nil && url.user == nil && url.password == nil && (url.port == nil || url.port == 443)
    }

    static func isErrorContentType(_ type: String?) -> Bool {
        let type = type?.lowercased() ?? ""
        return type.hasPrefix("text/") || type.contains("html") || type.contains("json") || type.contains("xml")
    }

    func request(for url: URL) -> URLRequest {
        var request = URLRequest(url: url)
        request.setValue(DizzyHTTPClient.userAgent, forHTTPHeaderField: "User-Agent")
        request.setValue(DizzyURL.site.absoluteString + "/", forHTTPHeaderField: "Referer")
        if Self.isSecure(url), url.host == DizzyURL.site.host { request.setValue(cookie, forHTTPHeaderField: "Cookie") }
        return request
    }

    func urlSession(_ session: URLSession, task: URLSessionTask, willPerformHTTPRedirection response: HTTPURLResponse,
                    newRequest request: URLRequest, completionHandler: @escaping (URLRequest?) -> Void) {
        guard let url = request.url, Self.isSecure(url) else { completionHandler(nil); return }
        // Build from scratch so neither cookies nor authorization survive a cross-origin redirect.
        completionHandler(self.request(for: url))
    }
}
