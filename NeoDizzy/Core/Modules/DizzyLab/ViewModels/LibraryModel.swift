import Foundation
import Observation

/// 当前账号的已购专辑列表。换账号时整个列表重建。
@Observable
final class LibraryModel {
    private(set) var userID: Int?
    private(set) var purchases: PagedList<PurchasedDisc>?

    func update(userID: Int?) {
        guard userID != self.userID else { return }
        self.userID = userID
        purchases = userID.map { id in
            PagedList { page in try await DizzyPages.shared.purchases(userID: id, page: page) }
        }
    }
}
