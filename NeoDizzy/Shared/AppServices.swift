import Foundation

/// 由 AppDelegate 持有一次，后台唤醒时也能恢复下载，不依赖某个页面出现。iOS 与 macOS 共用。
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
        }, localAccess: { [weak library] track in
            library?.access(for: track)
        }))
        account.restore()
    }

    func restore() async {
        await offlineLibrary.restore()
        await downloads.restore()
        player.restore()
    }
}
