import Foundation

nonisolated enum PurchaseKind: String, Codable, Sendable {
    case purchase = "dig"
    case boost = "boost"
}

/// Money is stored as integer fen. No floating-point rounding enters a payment URL.
nonisolated struct PurchaseAmount: Hashable, Comparable, Codable, Sendable {
    // A local input bound, not a claimed limit of the payment provider.
    static let maximumCents = 99_999_999
    let cents: Int

    init?(cents: Int) {
        guard (0...Self.maximumCents).contains(cents) else { return nil }
        self.cents = cents
    }

    init?(text: String) {
        let value = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard value.count <= 32,
              value.wholeMatch(of: #/[0-9]+(?:\.[0-9]{1,2})?/#) != nil else { return nil }
        let parts = value.split(separator: ".", omittingEmptySubsequences: false)
        guard let yuan = Int(parts[0]), yuan <= Self.maximumCents / 100 else { return nil }
        let fraction = parts.count == 2 ? String(parts[1]) : ""
        let fen = Int(fraction.padding(toLength: 2, withPad: "0", startingAt: 0)) ?? 0
        self.init(cents: yuan * 100 + fen)
    }

    /// Locale-independent text is used both in the amount field and checkout query.
    var text: String {
        let whole = cents / 100
        let fraction = cents % 100
        return fraction == 0 ? String(whole) : "\(whole).\(fraction < 10 ? "0" : "")\(fraction)"
    }

    var decimal: Decimal { Decimal(cents) / 100 }

    func adding(yuan: Int) -> PurchaseAmount? {
        guard yuan >= 0, yuan <= Self.maximumCents / 100 else { return nil }
        return PurchaseAmount(cents: cents + yuan * 100)
    }

    static func < (lhs: Self, rhs: Self) -> Bool { lhs.cents < rhs.cents }

    private enum CodingKeys: String, CodingKey { case cents }

    init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let cents = try container.decode(Int.self, forKey: .cents)
        guard let amount = Self(cents: cents) else {
            throw DecodingError.dataCorruptedError(forKey: .cents, in: container, debugDescription: "Amount is outside the supported range")
        }
        self = amount
    }
}

nonisolated struct PurchaseOffer: Equatable, Sendable {
    let discID: String
    let kind: PurchaseKind
    let minimum: PurchaseAmount
    let initialAmount: PurchaseAmount
    /// The current discounted album price, not its original list price.
    let basePrice: PurchaseAmount
    let commentLimit: Int
    let requiresLogin: Bool

    func validate(amountText: String, comment: String) throws -> PurchaseAmount {
        guard let amount = PurchaseAmount(text: amountText) else { throw PurchaseFailure.invalidAmount }
        guard amount >= minimum else { throw PurchaseFailure.belowMinimum(minimum) }
        // HTML textarea maxlength is measured in UTF-16 code units (emoji can use more than one).
        guard comment.utf16.count <= commentLimit else { throw PurchaseFailure.commentTooLong }
        return amount
    }

    /// Only construct this URL after the user explicitly starts checkout: loading it creates an order.
    func checkoutURL(amount: PurchaseAmount, comment: String) throws -> URL {
        _ = try validate(amountText: amount.text, comment: comment)
        guard !discID.isEmpty else { throw PurchaseFailure.unavailable }
        return DizzyURL.page("/albums/checkout_alipay/", query: [
            URLQueryItem(name: "id", value: discID),
            URLQueryItem(name: "q", value: "1"),
            URLQueryItem(name: "type", value: kind.rawValue),
            URLQueryItem(name: "price", value: amount.text),
            URLQueryItem(name: "commit", value: comment),
        ])
    }

    /// The site's purchase ratio truncates to a whole percent. Additional BOOST has no
    /// published cumulative total, and a free album has no meaningful price denominator.
    func boostPercentage(amount: PurchaseAmount) -> Int? {
        guard kind == .purchase, basePrice.cents > 0 else { return nil }
        return amount.cents * 100 / basePrice.cents
    }
}

nonisolated enum PurchaseFailure: LocalizedError {
    case invalidAmount
    case belowMinimum(PurchaseAmount)
    case commentTooLong
    case unavailable

    var errorDescription: String? {
        switch self {
        case .invalidAmount: "请输入有效金额，最多两位小数，上限为 ¥999999.99"
        case .belowMinimum(let minimum): "金额不能低于 ¥\(minimum.text)"
        case .commentTooLong: "附言超出网站的 100 字长度限制，表情可能占用多个字符"
        case .unavailable: "此商品暂不支持在 App 内购买，请在网页查看"
        }
    }
}
