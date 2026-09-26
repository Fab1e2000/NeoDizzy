import Foundation

nonisolated enum DownloadEvent: Sendable {
    case progress(UUID, Int64, Int64)
    case downloaded(UUID)
    case failed(UUID, String)
    case finishedBackgroundEvents
}

/// Never attaches credentials to background requests: iOS handles their redirects outside this process.
/// A short foreground request resolves the authenticated website redirect before enqueueing its signed target.
nonisolated final class DownloadTransport: NSObject, URLSessionDownloadDelegate, @unchecked Sendable {
    let events: AsyncStream<DownloadEvent>
    private let continuation: AsyncStream<DownloadEvent>.Continuation
    private let directory: URL
    private var session: URLSession!

    init(directory: URL, identifier: String) {
        self.directory = directory
        let stream = AsyncStream<DownloadEvent>.makeStream()
        events = stream.stream
        continuation = stream.continuation
        super.init()
        let configuration = URLSessionConfiguration.background(withIdentifier: identifier)
        configuration.httpCookieStorage = nil
        configuration.httpShouldSetCookies = false
        configuration.httpCookieAcceptPolicy = .never
        configuration.urlCredentialStorage = nil
        configuration.sessionSendsLaunchEvents = true
        configuration.isDiscretionary = false
        configuration.httpMaximumConnectionsPerHost = 2
        configuration.timeoutIntervalForRequest = 60
        configuration.timeoutIntervalForResource = 24 * 60 * 60
        let queue = OperationQueue()
        queue.maxConcurrentOperationCount = 1
        session = URLSession(configuration: configuration, delegate: self, delegateQueue: queue)
    }

    func start(url: URL, id: UUID) {
        var request = URLRequest(url: url)
        request.setValue(DizzyHTTPClient.userAgent, forHTTPHeaderField: "User-Agent")
        request.setValue(DizzyURL.site.absoluteString + "/", forHTTPHeaderField: "Referer")
        let task = session.downloadTask(with: request)
        task.taskDescription = id.uuidString
        task.resume()
    }

    func tasks() async -> [URLSessionTask] { await session.allTasks }

    func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask,
                    didWriteData bytesWritten: Int64, totalBytesWritten: Int64, totalBytesExpectedToWrite: Int64) {
        guard let id = downloadTask.taskDescription.flatMap(UUID.init(uuidString:)) else { return }
        if totalBytesWritten > Int64(SafeZipExtractor.Limits().archiveBytes) ||
            totalBytesExpectedToWrite > Int64(SafeZipExtractor.Limits().archiveBytes) {
            downloadTask.cancel()
            continuation.yield(.failed(id, DownloadFailure.archiveTooLarge.localizedDescription))
            return
        }
        continuation.yield(.progress(id, totalBytesWritten, totalBytesExpectedToWrite))
    }

    func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask, didFinishDownloadingTo location: URL) {
        guard let id = downloadTask.taskDescription.flatMap(UUID.init(uuidString:)) else { return }
        do {
            guard let response = downloadTask.response as? HTTPURLResponse,
                  (200..<300).contains(response.statusCode), !Self.isErrorContentType(response.mimeType) else {
                throw DownloadFailure.invalidResponse
            }
            try SafeZipExtractor.validateZIP(location)
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            let target = archiveURL(id)
            try? FileManager.default.removeItem(at: target)
            // URLSession deletes location after this delegate method returns; never defer this move into a Task.
            try FileManager.default.moveItem(at: location, to: target)
            continuation.yield(.downloaded(id))
        } catch {
            continuation.yield(.failed(id, Self.message(for: error)))
        }
    }

    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: (any Error)?) {
        guard let error, let id = task.taskDescription.flatMap(UUID.init(uuidString:)) else { return }
        continuation.yield(.failed(id, Self.message(for: error)))
    }

    func urlSessionDidFinishEvents(forBackgroundURLSession session: URLSession) {
        continuation.yield(.finishedBackgroundEvents)
    }

    func archiveURL(_ id: UUID) -> URL { directory.appendingPathComponent(id.uuidString + ".zip") }

    static func isErrorContentType(_ type: String?) -> Bool {
        let type = type?.lowercased() ?? ""
        return type.hasPrefix("text/") || type.contains("html") || type.contains("json") || type.contains("xml")
    }

    static func message(for error: any Error) -> String {
        if let error = error as? DownloadFailure { return error.localizedDescription }
        if let error = error as? DizzyError { return error.localizedDescription }
        if let error = error as? OfflineLibraryError { return error.localizedDescription }
        // NSError descriptions can contain the full signed URL. Never save or display them.
        if (error as NSError).domain == NSURLErrorDomain { return "网络连接失败，请重试下载" }
        return "下载或保存失败，请检查可用空间和文件夹权限后重试"
    }
}
