import Foundation
import Observation

@Observable
final class CommunityProfileModel {
    let userID: Int
    var section: ProfileSection = .music
    var profile: CommunityProfile?
    var failure: String?
    var loading = false
    var page = 0
    var discs: [DiscSummary] = []
    var labels: [SearchLabel] = []
    var reviews: [ReviewSummary] = []
    private var generation = 0
    init(userID: Int) { self.userID = userID }
    func reset() async {
        generation += 1
        loading = false; page = 0; profile = nil; discs = []; labels = []; reviews = []; failure = nil
        await next()
    }
    func next() async {
        guard !loading else { return }
        loading = true; failure = nil
        let gen = generation
        do {
            let result = try await DizzyCommunity.shared.profile(userID, section: section, page: page + 1)
            try Task.checkCancellation()
            guard gen == generation else { return }
            profile = result; page += 1
            var ids = Set(discs.map(\.id)); discs += result.discs.filter { ids.insert($0.id).inserted }
            var names = Set(labels.map(\.id)); labels += result.labels.filter { names.insert($0.id).inserted }
            var rids = Set(reviews.map(\.id)); reviews += result.reviews.filter { rids.insert($0.id).inserted }
        } catch is CancellationError {} catch { if gen == generation { failure = error.localizedDescription } }
        if gen == generation { loading = false }
    }
}

extension Notification.Name {
    static let dizzyFollowingDidChange = Notification.Name("dizzyFollowingDidChange")
}
