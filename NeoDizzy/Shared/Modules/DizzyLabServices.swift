import Foundation

/// Platform session, purchases and downloads stay together, including background restoration.
final class DizzyLabServices {
    let browsingHistory = BrowsingHistoryStore()
    let account = AccountStore()
    let downloads: DownloadStore
    let purchases: PurchaseStore

    init(library: OfflineLibraryStore) {
        let account = account
        purchases = PurchaseStore(accountID: { [weak account] in
            guard let account, !account.isSessionExpired else { return nil }
            return account.account?.userID
        })
        downloads = DownloadStore(library: library, migrateLegacy: DizzyLabDownloadProvider.migrate)
        downloads.register(DizzyLabDownloadProvider(library: library))
        account.restore()
    }
    func restore() async { await downloads.restore() }
}
