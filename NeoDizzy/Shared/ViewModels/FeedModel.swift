import Foundation
import Observation

/// 关注动态：已关注社团的新作，按社团分组。需要有效的 token。
@Observable
final class FeedModel {
    private(set) var userID: Int?
    private(set) var groups: PagedList<FeedGroup>?

    func update(userID: Int?) {
        guard userID != self.userID else { return }
        self.userID = userID
        groups = userID.map { _ in PagedList { page in try await DizzyAPI.shared.feed(page: page) } }
    }
}
