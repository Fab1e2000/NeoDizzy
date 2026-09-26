import Foundation

/// pack：几张专辑打包优惠出售。
nonisolated struct PackSummary: Hashable, Identifiable, Sendable {
    let id: String
    let title: String
    let coverURL: URL?
    let labelName: String?
    let price: Double?
}

/// pack 页 `/pack/?pk=<id>`。
nonisolated struct PackDetail: Sendable {
    let id: String
    let title: String
    let coverURL: URL?
    let labelName: String?
    let discs: [DiscSummary]
    /// 支付宝价格（元）。
    let price: Double?
    /// 网页上的说明，例如「购买此pack以20%折扣的价格（原价：105.0元）获得：…」。
    let offer: String?
    let description: String
}
