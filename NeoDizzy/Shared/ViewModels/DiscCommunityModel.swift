import Foundation
import Observation

@Observable
final class DiscCommunityModel {
    let discID: String
    let comments: PagedList<DiscComment>
    let reviews: PagedList<ReviewSummary>
    var context: DiscCommunityContext?
    var likes: DiscLikes?
    var failure: String?
    var busy = false
    var loaded = false
    init(discID: String) {
        self.discID = discID
        comments = PagedList { try await DizzyCommunity.shared.comments(discID, page: $0) }
        reviews = PagedList { try await DizzyCommunity.shared.reviews(discID, page: $0) }
    }
    func refresh() async {
        do {
            async let ctx = DizzyCommunity.shared.context(discID)
            async let counts = DizzyCommunity.shared.likes(discID)
            let values = try await (ctx, counts)
            try Task.checkCancellation()
            context = values.0; likes = values.1; failure = nil; loaded = true
        } catch is CancellationError {} catch { failure = error.localizedDescription }
    }
    func act(_ work: () async throws -> Void) async -> Bool {
        guard !busy else { return false }
        busy = true; failure = nil
        defer { busy = false }
        do {
            try await work()
            await refresh()
            await comments.reload()
            return true
        } catch is CancellationError { return false }
        catch { failure = error.localizedDescription; return false }
    }
}
