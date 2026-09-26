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

/// 由 AppDelegate 持有一次，后台唤醒时也能恢复下载，不依赖某个页面出现。
final class AppServices {
    let browsingHistory = BrowsingHistoryStore()
    let account = AccountStore()
    let offlineLibrary: OfflineLibraryStore
    let downloads: DownloadStore
    let purchases: PurchaseStore
    let player: PlayerStore

    init() {
        let account = account
        purchases = PurchaseStore(accountID: { [weak account] in
            guard let account, !account.isSessionExpired else { return nil }
            return account.account?.userID
        })
        let library = OfflineLibraryStore()
        offlineLibrary = library
        downloads = DownloadStore(library: library)
        player = PlayerStore(resolver: StreamResolver(localFile: { [weak library] track in
            library?.localFile(for: track)
        }))
        account.restore()
    }

    func restore() async {
        await offlineLibrary.restore()
        await downloads.restore()
        player.restore()
    }
}
