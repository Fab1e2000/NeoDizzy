import Foundation

/// The app delegate forwards iOS background-session wakeups here, including cold launches.
enum BackgroundDownloadBridge {
    static let identifier = "com.elsterlee.NeoDizzy.album-downloads"
    private static var completion: (() -> Void)?
    private static var finishedBeforeHandler = false

    static func handleEvents(identifier: String, completionHandler: @escaping () -> Void) {
        guard identifier == Self.identifier else { completionHandler(); return }
        if finishedBeforeHandler {
            finishedBeforeHandler = false
            completionHandler()
        } else {
            completion = completionHandler
        }
    }

    static func finishEvents() {
        guard let handler = completion else { finishedBeforeHandler = true; return }
        completion = nil
        handler()
    }
}
