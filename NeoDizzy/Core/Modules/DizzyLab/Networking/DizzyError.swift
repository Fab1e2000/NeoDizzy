import Foundation

nonisolated enum DizzyError: LocalizedError, Equatable {
    /// 网络不通、超时等，附带系统给出的说明。
    case network(String)
    case httpStatus(Int)
    /// 接口返回的 JSON 和预期不一致。网站出错时也返回 200 和一个 HTML 错误页，同样落在这里。
    case decoding(String)
    /// 页面结构和预期不一致，多半是网站改版了。参数是页面名称。
    case parsing(String)
    /// 需要登录才能用的功能。
    case notLoggedIn
    /// 网站不再接受保存的登录凭据，需要重新登录。
    case sessionExpired
    /// 登录失败，附带网站给出的原因或通用说明。
    case loginFailed(String)

    var errorDescription: String? {
        switch self {
        case .network(let message):
            String(localized: "网络连接失败：\(message)")
        case .httpStatus(let code):
            String(localized: "网站返回了错误（HTTP \(code)）")
        case .decoding:
            String(localized: "网站返回的数据无法识别")
        case .parsing:
            String(localized: "页面内容无法识别，网站可能改版了")
        case .notLoggedIn:
            String(localized: "请先登录 DizzyLab 账号")
        case .sessionExpired:
            String(localized: "登录已失效，请重新登录")
        case .loginFailed(let message):
            message
        }
    }

    /// 网站返回的不是预期的 JSON（多半是错误页）。
    var isUnrecognizedResponse: Bool {
        if case .decoding = self { true } else { false }
    }
}
