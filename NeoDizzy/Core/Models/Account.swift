import Foundation

/// 登录的 DizzyLab 账号。
nonisolated struct Account: Codable, Equatable, Sendable {
    let userID: Int
    var nickname: String
    var avatarURL: URL?
}

/// 已购专辑页里的一张专辑。
nonisolated struct PurchasedDisc: Hashable, Identifiable, Sendable {
    let disc: DiscSummary
    /// 网页原文里的日期，例如 `2026-09-05`。
    let purchaseDate: String?

    var id: String { disc.id }
}

/// 关注动态里的一组：某个已关注社团最近发布的作品。
nonisolated struct FeedGroup: Hashable, Identifiable, Sendable {
    let labelID: Int
    let labelName: String
    let labelCoverURL: URL?
    /// 网页原文里的时间（ISO 8601）。
    let addDate: String?
    let discs: [DiscSummary]

    var id: String { "\(labelID)-\(addDate ?? "")" }
}
