import Foundation

/// 首页的三类专辑列表，对应 `getdiscs` 的 `type` 参数。
nonisolated enum DiscCategory: String, CaseIterable, Identifiable, Sendable {
    case album, ep, dig

    var id: String { rawValue }

    var title: String {
        switch self {
        case .album: String(localized: "数字专辑")
        case .ep: String(localized: "单曲EP")
        case .dig: String(localized: "下载商品")
        }
    }
}

/// 列表里的一张专辑。JSON 接口给的字段最全；社团页、标签页、搜索页的 HTML 卡片只有其中一部分，
/// 所以除了 ID、标题和封面，其余都是可选的。
nonisolated struct DiscSummary: Hashable, Identifiable, Sendable {
    let id: String
    let title: String
    let coverURL: URL?
    var labelName: String?
    var labelID: Int?
    var price: PriceTag?
    var tags: [String] = []
    var likes: Int?
    var isHiRes = false
}

/// 网页上的价格标注。
nonisolated enum PriceTag: Hashable, Sendable {
    case free
    /// 不在售、也不在预售，只能用兑换码获得。
    case redeem
    case price(Double)
    /// 限时优惠：原价、现价。
    case deal(original: Double, current: Double)

    /// 与网页一致：价格不大于 0 为免费；不在售且不在预售为兑换；否则显示价格。
    init(price: Double, onSell: Bool, isPreselling: Bool) {
        if price <= 0 {
            self = .free
        } else if !onSell && !isPreselling {
            self = .redeem
        } else {
            self = .price(price)
        }
    }

    var text: String {
        switch self {
        case .free: String(localized: "免费")
        case .redeem: String(localized: "兑换")
        case .price(let value), .deal(_, let value): Self.yuan(value)
        }
    }

    /// `¥45`、`¥4.5`：整数价格不带小数。
    static func yuan(_ value: Double) -> String {
        value.rounded() == value
            ? "¥\(Int(value))"
            : "¥" + value.formatted(.number.precision(.fractionLength(0...2)))
    }
}

/// 首页「限时优惠」里的一项。
nonisolated struct Deal: Hashable, Identifiable, Sendable {
    let disc: DiscSummary
    /// 网页原文，例如「2026年9月30日 截止」。
    let deadline: String?

    var id: String { disc.id }
}

/// 专辑详情，来自 `getthisdicsinfo`。
nonisolated struct DiscDetail: Sendable {
    let summary: DiscSummary
    /// 网页原文，例如 `2026-06-28`。
    let releaseDate: String?
    /// 专辑介绍和第二段介绍（曲目表、制作人员等），已把 `\r\n` 统一为换行并去掉首尾空白。
    let description: String
    let credits: String
    let labelDescription: String
    let hasGift: Bool
    let tracks: [Track]
    /// 曲号 → 播放地址。地址带时间签名，约一小时后过期，不随曲目保存。
    let streams: [String: URL]

    var id: String { summary.id }
}
