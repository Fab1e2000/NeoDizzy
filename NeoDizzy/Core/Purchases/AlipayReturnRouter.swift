import Foundation

/// 支付宝已生成的 SafePay 调起信封只修改来源 App；订单串和网站 return_url 保持原值。
/// 此信封格式见支付宝官方 SDK 的 fromScheme 路径。未知格式保留原有网页付款流程。
nonisolated enum AlipayReturnRouter {
    static let scheme = "neodizzy-pay"

    /// 回调仅用于触发网站到账核验；不读取或信任 URL 中的支付状态。
    static func isCallback(_ url: URL) -> Bool {
        guard let components = URLComponents(url: url, resolvingAgainstBaseURL: false) else { return false }
        return components.scheme?.lowercased() == scheme
            && components.host?.lowercased() == "safepay"
            && ["", "/"].contains(components.path)
            && components.user == nil && components.password == nil
            && components.port == nil && components.fragment == nil
    }

    /// 不根据 H5 地址自行构造订单，也不改写 platformapi 链接中的嵌套 URL。
    /// 返回 nil 说明格式未知，调用方应使用原链接并提示可能需要手动返回。
    static func paymentURL(from url: URL) -> URL? {
        guard var components = URLComponents(url: url, resolvingAgainstBaseURL: false),
              let originalScheme = components.scheme?.lowercased(),
              ["alipay", "alipays"].contains(originalScheme),
              components.user == nil, components.password == nil,
              components.port == nil, components.fragment == nil,
              let encoded = components.percentEncodedQuery else { return nil }

        let host = components.host?.lowercased()
        let path = components.path.lowercased()
        let isEnvelopeRoute = host == "alipayclient" && ["", "/"].contains(path)
        let isPlatformRoute = host == "platformapi" && path == "/startapp"
        guard isEnvelopeRoute || isPlatformRoute else { return nil }

        // 当前 H5 SDK 入口将此字段作为订单 URL 外层参数追加。只替换已存在的明确字段，
        // 其余 query 字节原样保留，不推测未知 URL 应该新增哪些参数。
        var fields = encoded.components(separatedBy: "&")
        let callbackFields = fields.indices.filter { index in
            fields[index].components(separatedBy: "=").first?.removingPercentEncoding == "MQPSourceAppScheme"
        }
        if !callbackFields.isEmpty {
            guard callbackFields.count == 1, let index = callbackFields.first,
                  // JSON 信封只有整体编码后，& 才能明确表示外层参数。
                  isPlatformRoute || fields.first?.lowercased().hasPrefix("%7b") == true else { return nil }
            let name = fields[index].components(separatedBy: "=")[0]
            fields[index] = name + "=" + scheme
            components.percentEncodedQuery = fields.joined(separator: "&")
            return components.url
        }

        guard isEnvelopeRoute,
              let decoded = encoded.removingPercentEncoding,
              let data = decoded.data(using: .utf8),
              var envelope = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any],
              envelope["requestType"] as? String == "SafePay",
              envelope["fromAppUrlScheme"] == nil || envelope["fromAppUrlScheme"] is String,
              let order = envelope["dataString"] as? String, !order.isEmpty else { return nil }

        envelope["fromAppUrlScheme"] = scheme
        guard let rewritten = try? JSONSerialization.data(withJSONObject: envelope, options: [.sortedKeys]),
              let json = String(data: rewritten, encoding: .utf8),
              // JSON 是整个 query，不能把订单中的 &、+、%、# 当成 URL 分隔符。
              let query = json.addingPercentEncoding(withAllowedCharacters: .alphanumerics) else { return nil }
        components.percentEncodedQuery = query
        return components.url
    }
}
