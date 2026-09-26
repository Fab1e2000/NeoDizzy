import Foundation

/// 访问 DizzyLab 的唯一出口：统一 UA、Referer、超时，并限制同时进行的请求数。
/// App 只在用户操作时按需请求，不做批量抓取（见 docs/PLAN.md「请求礼貌」）。
nonisolated final class DizzyHTTPClient: Sendable {
    static let shared = DizzyHTTPClient()

    /// iPhone Safari 的 UA。网站按 UA 区分手机和桌面页面，付款跳转也依赖手机 UA。
    static let userAgent = "Mozilla/5.0 (iPhone; CPU iPhone OS 27_0 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/27.0 Mobile/15E148 Safari/604.1"

    private let session: URLSession
    private let gate = RequestGate(limit: 4)

    init(session: URLSession = URLSession(configuration: .dizzy)) {
        self.session = session
    }

    func data(path: String, query: [URLQueryItem] = []) async throws -> Data {
        var request = URLRequest(url: DizzyURL.page(path, query: query))
        request.setValue(DizzyURL.site.absoluteString + "/", forHTTPHeaderField: "Referer")
        return try await perform(request).0
    }

    /// 文件大小（字节），用 HEAD 请求获取，不下载内容。
    func contentLength(of url: URL) async throws -> Int64? {
        var request = URLRequest(url: url)
        request.httpMethod = "HEAD"
        let length = try await perform(request).1.expectedContentLength
        return length > 0 ? length : nil
    }

    private func perform(_ request: URLRequest) async throws -> (Data, URLResponse) {
        var request = request
        request.setValue(Self.userAgent, forHTTPHeaderField: "User-Agent")

        await gate.acquire()
        defer { Task { await gate.release() } }
        try Task.checkCancellation()

        let result: (Data, URLResponse)
        do {
            result = try await session.data(for: request)
        } catch let error as URLError where error.code == .cancelled {
            throw CancellationError()
        } catch let error as URLError {
            debugLog("请求失败 \(request.url?.absoluteString ?? "")：\(error.code.rawValue) \(error.localizedDescription)")
            throw DizzyError.network(error.localizedDescription)
        }
        if let status = (result.1 as? HTTPURLResponse)?.statusCode, !(200..<300).contains(status) {
            debugLog("请求失败 \(request.url?.absoluteString ?? "")：HTTP \(status)")
            throw DizzyError.httpStatus(status)
        }
        return result
    }

    func json<T: Decodable & Sendable>(_ type: T.Type, path: String, query: [URLQueryItem] = []) async throws -> T {
        let data = try await data(path: path, query: query)
        do {
            return try JSONDecoder().decode(T.self, from: data)
        } catch {
            throw DizzyError.decoding(String(describing: error))
        }
    }

    func html(path: String, query: [URLQueryItem] = []) async throws -> String {
        let data = try await data(path: path, query: query)
        return String(decoding: data, as: UTF8.self)
    }
}

nonisolated extension URLSessionConfiguration {
    /// 断网时立即失败而不是等待网络恢复；单个请求最多 30 秒，超时后界面显示错误，不会一直转圈。
    static var dizzy: URLSessionConfiguration {
        let configuration = URLSessionConfiguration.default
        configuration.waitsForConnectivity = false
        configuration.timeoutIntervalForRequest = 15
        configuration.timeoutIntervalForResource = 30
        return configuration
    }
}

/// 简单的计数信号量：超过上限的请求排队等待。
private actor RequestGate {
    private let limit: Int
    private var running = 0
    private var waiting: [CheckedContinuation<Void, Never>] = []

    init(limit: Int) {
        self.limit = limit
    }

    func acquire() async {
        if running < limit {
            running += 1
            return
        }
        await withCheckedContinuation { waiting.append($0) }
    }

    func release() {
        if waiting.isEmpty {
            running -= 1
        } else {
            // 名额直接交给排队的请求，running 不变。
            waiting.removeFirst().resume()
        }
    }
}
