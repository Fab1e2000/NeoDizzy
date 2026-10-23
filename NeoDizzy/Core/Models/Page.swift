import Foundation

/// 分页列表的一页。页码从 1 开始，与网页的 `?page=` 一致。
nonisolated struct Page<Item: Sendable>: Sendable {
    let items: [Item]
    let hasMore: Bool
}
