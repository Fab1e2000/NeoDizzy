import Foundation

/// DizzyLab owns its account and purchases; downloads are borrowed from the host.
final class DizzyLabServices {
    let account = AccountStore()
    let downloads: DownloadStore
    let purchases: PurchaseStore

    init(library: OfflineLibraryStore, downloads: DownloadStore) {
        let account = account
        purchases = PurchaseStore(accountID: { [weak account] in
            guard let account, !account.isSessionExpired else { return nil }
            return account.account?.userID
        })
        self.downloads = downloads
        account.restore()
        // 浏览记录功能已移除，清掉以前存下的记录。
        UserDefaults.standard.removeObject(forKey: "browsedDiscs.v1")
    }
    func restore() async {}
}
