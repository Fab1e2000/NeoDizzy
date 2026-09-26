import Foundation

nonisolated struct CommunityUser: Identifiable, Hashable, Sendable {
    let id: Int
    let name: String
    let avatarURL: URL?
}
nonisolated struct DiscComment: Identifiable, Sendable {
    let id: String
    let user: CommunityUser
    let text: String
    let badge: String?
}
nonisolated struct DiscLikes: Decodable, Sendable {
    let likes: Int
    let ilikethis: Bool
}
nonisolated struct DiscCommunityContext: Sendable {
    let userID: Int?
    let csrf: String?
    let myComment: String?
    let commentLimit: Int
    let canComment: Bool
}
nonisolated struct ReviewSummary: Identifiable, Sendable {
    let id: Int
    let title: String
    let excerpt: String
    let user: CommunityUser?
    let date: String?
}
nonisolated struct ReviewDetail: Sendable {
    let title: String
    let user: CommunityUser?
    let text: String
    let images: [URL]
}
nonisolated struct Supporter: Identifiable, Sendable {
    let rank: Int
    let user: CommunityUser
    let bio: String
    var id: Int { user.id }
}
nonisolated enum ProfileSection: String, CaseIterable, Identifiable, Sendable {
    case music, review, following, likes
    var id: String { rawValue }
    var title: String {
        switch self { case .music: "已购"; case .review: "repo"; case .following: "关注"; case .likes: "+2 dB" }
    }
}
nonisolated struct CommunityProfile: Sendable {
    let user: CommunityUser
    let bio: String
    let joined: String
    let discs: [DiscSummary]
    let labels: [SearchLabel]
    let reviews: [ReviewSummary]
    let hasMore: Bool
}
nonisolated struct ShuffleTrack: Sendable {
    let track: Track
    let stream: URL
    let label: String
    let tags: [String]
}

nonisolated enum CommunityFailure: LocalizedError, Equatable {
    case feedback(String)
    var errorDescription: String? { if case .feedback(let message) = self { message } else { nil } }
}
