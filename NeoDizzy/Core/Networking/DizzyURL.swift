import Foundation

/// 网站、CDN 和播放地址的规则。接口细节见 docs/SITE_API.md。
nonisolated enum DizzyURL {
    static let site = URL(string: "https://www.dizzylab.net")!
    static let media = URL(string: "https://cdn.dizzylab.net/media/")!

    // MARK: 网页地址（「在网页中打开」）

    static func disc(_ id: String) -> URL { page("/d/\(pathSegment(id))/") }
    static func label(_ name: String) -> URL { page("/l/\(pathSegment(name))/") }
    static func pack(_ id: String) -> URL { page("/pack/", query: [URLQueryItem(name: "pk", value: id)]) }
    static func tag(_ tag: String) -> URL { page("/albums/tags/", query: [URLQueryItem(name: "tag", value: tag)]) }
    static func search(_ keyword: String) -> URL { page("/search/", query: [URLQueryItem(name: "s", value: keyword)]) }

    /// 拼出站内地址。`percentEncodedPath` 里的每一段需要调用方用 `pathSegment` 转义好。
    static func page(_ percentEncodedPath: String, query: [URLQueryItem] = []) -> URL {
        var components = URLComponents()
        components.scheme = site.scheme
        components.host = site.host
        components.percentEncodedPath = percentEncodedPath
        if !query.isEmpty {
            // 自己转义查询值：URLComponents 会原样保留 `& = +`，
            // Django 会把 `+` 当成空格，搜「C++」就变成了「C  」。
            components.percentEncodedQueryItems = query.map {
                URLQueryItem(name: $0.name, value: $0.value.map(queryValue))
            }
        }
        return components.url!
    }

    /// 用户的已购专辑页。
    static func purchases(userID: Int) -> URL { page("/u/\(userID)/music/") }
    static let login = page("/albums/login/")

    /// 表单内容（`application/x-www-form-urlencoded`），值的转义规则与查询参数相同。
    static func formEncoded(_ fields: [(String, String)]) -> String {
        fields.map { "\(queryValue($0.0))=\(queryValue($0.1))" }.joined(separator: "&")
    }

    /// 路径中的一段，例如社团名 `obscuRE TRAX`、`雪人Snowman`。`/` 也要转义，避免被拆成两段。
    static func pathSegment(_ value: String) -> String {
        value.addingPercentEncoding(withAllowedCharacters: unreservedCharacters) ?? value
    }

    private static func queryValue(_ value: String) -> String {
        value.addingPercentEncoding(withAllowedCharacters: unreservedCharacters) ?? value
    }

    private static let unreservedCharacters = CharacterSet(
        charactersIn: "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789-._~"
    )

    // MARK: 图片

    /// 网站给出的图片地址：完整地址原样使用；`getlabels` 里的 `cover/xxx.jpg` 这类相对路径补全到 CDN，
    /// 并加上网站列表用的 `!cover` 缩略图样式。地址里常有中文文件名，`URL(string:)` 会自动转义。
    static func image(_ string: String?) -> URL? {
        guard let string = string?.trimmingCharacters(in: .whitespacesAndNewlines), !string.isEmpty else {
            return nil
        }
        if string.hasPrefix("http://") || string.hasPrefix("https://") {
            return URL(string: string)
        }
        if string.hasPrefix("/") {
            return URL(string: string, relativeTo: site)?.absoluteURL
        }
        return URL(string: string + "!cover", relativeTo: media)?.absoluteURL
    }

    /// CDN 的 `!cover` 会把透明 PNG 转成白底 JPEG，白色社团字标因此变成整块白色。
    /// 仅头像请求取回已知 CDN 上的 PNG 原图；不改专辑封面、第三方 URL 或其他缩略图样式。
    static func avatar(_ url: URL?) -> URL? {
        guard let url,
              url.host?.lowercased() == media.host,
              url.path.hasPrefix("/media/"),
              url.path.lowercased().hasSuffix(".png!cover"),
              var components = URLComponents(url: url, resolvingAgainstBaseURL: true) else {
            return url
        }
        components.path = String(components.path.dropLast("!cover".count))
        return components.url ?? url
    }

    /// 网页懒加载前的占位图，不是真正的封面。
    static func isPlaceholderImage(_ url: URL) -> Bool {
        url.lastPathComponent.hasPrefix("holder_")
    }

    // MARK: 播放地址

    /// 形如 `https://streaming.dizzylab.net/<yyyyMMddHHmm>/<md5>/<discid>/preview/<n>.mp3`。
    /// 时间是东八区的过期时间，约为请求时间加 1 小时；`preview` 是试听片段（长度各专辑不同），`full` 是完整版。
    static func isPreviewStream(_ url: URL) -> Bool {
        url.pathComponents.contains("preview")
    }

    static func streamExpiry(_ url: URL) -> Date? {
        guard let stamp = url.pathComponents.first(where: { $0.count == 12 && $0.allSatisfy(\.isASCIIDigit) }) else {
            return nil
        }
        return streamStampFormatter.date(from: stamp)
    }

    private static let streamStampFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(identifier: "Asia/Shanghai")
        formatter.dateFormat = "yyyyMMddHHmm"
        return formatter
    }()
}

private extension Character {
    nonisolated var isASCIIDigit: Bool { isASCII && isNumber }
}
