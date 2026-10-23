import Foundation

/// 社团列表里的一项，来自 `getlabels`。
nonisolated struct LabelSummary: Hashable, Identifiable, Sendable {
    let id: Int
    let name: String
    let coverURL: URL?
    let description: String
    /// 最近的几张作品，只有 ID、标题和封面。
    let recentDiscs: [DiscSummary]
}

/// 社团页 `/l/<名字>/`。网站在一页里列出社团的全部作品，没有分页。
nonisolated struct LabelPage: Sendable {
    let name: String
    let coverURL: URL?
    let description: String
    let followerCount: Int?
    /// 网页原文，例如「obscuRE TRAX成立于2024年06月21日」。
    let history: [String]
    let packs: [PackSummary]
    let discs: [DiscSummary]
}
