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
    private var activeSection: ProfileSection?
    private let fetch: (Int, ProfileSection, Int) async throws -> CommunityProfile
    init(userID: Int, fetch: @escaping (Int, ProfileSection, Int) async throws -> CommunityProfile = {
        try await DizzyCommunity.shared.profile($0, section: $1, page: $2)
    }) { self.userID = userID; self.fetch = fetch }
    func loadSectionIfNeeded() async {
        guard activeSection != section || page == 0 else { return }
        await reset()
    }
    func reset(keepingItems: Bool = false) async {
        let retain = keepingItems && activeSection == section
        activeSection = section
        generation += 1
        loading = false; page = 0; failure = nil
        if !retain { discs = []; labels = []; reviews = [] }
        await next()
    }
    func next() async {
        guard !loading else { return }
        loading = true; failure = nil
        let gen = generation
        do {
            let result = try await fetch(userID, section, page + 1)
            try Task.checkCancellation()
            guard gen == generation else { return }
            if page == 0 { discs = []; labels = []; reviews = [] }
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
