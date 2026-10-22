import AVFoundation
import Foundation
import UniformTypeIdentifiers

/// A single sequential HTTP response feeds both AVFoundation and a disk spool.
/// All mutable state and file IO are confined to queue, including URLSession delegates.
/// Architecture reference: neekeetab/CachingPlayerItem (MIT); no whole-file Data buffer.
nonisolated final class ProgressiveAudioLoader: NSObject, AVAssetResourceLoaderDelegate, URLSessionDataDelegate, @unchecked Sendable {
    private let queue = DispatchQueue(label: "NeoDizzy.AudioSpool", qos: .userInitiated)
    private let configuration: URLSessionConfiguration
    private let url: URL
    private let file: URL
    private let writer: FileHandle
    private let reader: FileHandle
    private let completion: @Sendable (URL?, Int64, String) -> Void
    private var session: URLSession?
    private var pending = Set<AVAssetResourceLoadingRequest>()
    private var received: Int64 = 0
    private var expected: Int64 = -1
    private var contentType: String?
    private var fileExtension: String
    private var finished = false
    private var failure: Error?
    private var started = false
    private let maxBytes: Int64 = 512 * 1_024 * 1_024

    init(url: URL, directory: URL, configuration: URLSessionConfiguration = .ephemeral, completion: @escaping @Sendable (URL?, Int64, String) -> Void) throws {
        self.url = url; self.completion = completion; self.configuration = configuration
        fileExtension = url.pathExtension.lowercased()
        file = directory.appendingPathComponent(UUID().uuidString + ".partial")
        guard FileManager.default.createFile(atPath: file.path, contents: nil) else { throw PlaybackError.failed }
        writer = try FileHandle(forWritingTo: file)
        reader = try FileHandle(forReadingFrom: file)
        super.init()
    }
    func makeItem() -> AVPlayerItem {
        var components = URLComponents(url: url, resolvingAgainstBaseURL: false)!
        components.scheme = "neodizzy-audio"
        let asset = AVURLAsset(url: components.url!)
        asset.resourceLoader.setDelegate(self, queue: queue)
        return AVPlayerItem(asset: asset)
    }
    func cancel() { queue.async { self.finish(URLError(.cancelled)) } }
    func resourceLoader(_ resourceLoader: AVAssetResourceLoader, shouldWaitForLoadingOfRequestedResource request: AVAssetResourceLoadingRequest) -> Bool {
        pending.insert(request)
        if !started && !finished {
            started = true
            configuration.urlCache = nil
            configuration.requestCachePolicy = .reloadIgnoringLocalCacheData
            configuration.timeoutIntervalForRequest = 30
            let delegateQueue = OperationQueue(); delegateQueue.maxConcurrentOperationCount = 1; delegateQueue.underlyingQueue = queue
            let session = URLSession(configuration: configuration, delegate: self, delegateQueue: delegateQueue)
            self.session = session
            var request = URLRequest(url: url)
            request.setValue("identity", forHTTPHeaderField: "Accept-Encoding")
            session.dataTask(with: request).resume()
        }
        fulfill(); return true
    }
    func resourceLoader(_ resourceLoader: AVAssetResourceLoader, didCancel request: AVAssetResourceLoadingRequest) { pending.remove(request) }
    func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive response: URLResponse, completionHandler: @escaping (URLSession.ResponseDisposition) -> Void) {
        guard !finished, let response = response as? HTTPURLResponse, response.statusCode == 200,
              !DownloadTransport.isErrorContentType(response.mimeType), response.expectedContentLength != 0,
              response.expectedContentLength <= maxBytes else {
            completionHandler(.cancel); finish(PlaybackError.failed); return
        }
        expected = response.expectedContentLength
        let type = response.mimeType.flatMap { UTType(mimeType: $0) } ?? UTType(filenameExtension: fileExtension)
        contentType = type?.identifier ?? UTType.audio.identifier
        if let ext = type?.preferredFilenameExtension { fileExtension = ext }
        completionHandler(.allow); fulfill()
    }
    func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive data: Data) {
        guard !finished else { return }
        do {
            guard received + Int64(data.count) <= maxBytes else { throw PlaybackError.failed }
            try writer.write(contentsOf: data); received += Int64(data.count)
            fulfill()
        } catch { finish(error) }
    }
    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        if let error { finish(error) }
        else if received <= 0 || (expected >= 0 && received != expected) { finish(PlaybackError.failed) }
        else { finish(nil) }
    }
    private func finish(_ error: Error?) {
        guard !finished else { return }
        finished = true; failure = error
        if expected < 0 { expected = received }
        try? writer.synchronize()
        session?.invalidateAndCancel(); session = nil
        fulfill()
        // Hand off a separate file so rapid switching cannot delete it before the index commits.
        if error == nil {
            let ready = file.deletingPathExtension().appendingPathExtension("ready")
            do { try FileManager.default.copyItem(at: file, to: ready); completion(ready, received, fileExtension) }
            catch { completion(nil, 0, fileExtension) }
        } else { completion(nil, 0, fileExtension) }
    }
    private func fulfill() {
        for request in pending {
            if let failure { request.finishLoading(with: failure); pending.remove(request); continue }
            if let info = request.contentInformationRequest, let contentType, expected >= 0 {
                info.contentType = contentType; info.contentLength = expected; info.isByteRangeAccessSupported = true
            }
            guard let data = request.dataRequest else {
                if contentType != nil && expected >= 0 { request.finishLoading(); pending.remove(request) }; continue
            }
            var offset = max(data.requestedOffset, data.currentOffset)
            let end = data.requestsAllDataToEndOfResource ? (expected >= 0 ? expected : Int64.max) : data.requestedOffset + Int64(data.requestedLength)
            do {
                while offset < min(received, end) {
                    try reader.seek(toOffset: UInt64(offset))
                    let chunk = try reader.read(upToCount: Int(min(64 * 1_024, min(received, end) - offset))) ?? Data()
                    guard !chunk.isEmpty else { throw PlaybackError.failed }
                    data.respond(with: chunk); offset += Int64(chunk.count)
                }
                if offset >= end || (finished && offset >= received) { request.finishLoading(); pending.remove(request) }
            } catch { request.finishLoading(with: error); pending.remove(request) }
        }
    }
    deinit {
        try? writer.close(); try? reader.close()
        try? FileManager.default.removeItem(at: file)
    }
}
