import SwiftUI
import UIKit

@main
struct NeoDizzyApp: App {
    @UIApplicationDelegateAdaptor(NeoDizzyAppDelegate.self) private var appDelegate

    var body: some Scene {
        WindowGroup {
            RootView(services: appDelegate.services)
        }
    }
}

/// 系统在后台下载完成后唤醒 App，把事件交回同一个后台会话。
final class NeoDizzyAppDelegate: NSObject, UIApplicationDelegate {
    let services = AppServices()

    func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil
    ) -> Bool {
        Task { await services.restore() }
        return true
    }

    func application(
        _ application: UIApplication,
        handleEventsForBackgroundURLSession identifier: String,
        completionHandler: @escaping () -> Void
    ) {
        BackgroundDownloadBridge.handleEvents(identifier: identifier, completionHandler: completionHandler)
    }
}
