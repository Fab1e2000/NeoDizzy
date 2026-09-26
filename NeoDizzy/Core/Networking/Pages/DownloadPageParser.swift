import Foundation
import SwiftSoup
import SwiftSoup

nonisolated enum DownloadPageParser {
    static func parse(_ html: String, discID: String) throws -> [DownloadOption] {
        try HTML.parsing("专辑下载") {
            let document = try HTML.document(html, page: "专辑下载")
            var seen = Set<String>()
            return try document.select("a[href]").array().compactMap { link in
                let href = try link.attr("href")
                guard let url = URL(string: href, relativeTo: DizzyURL.site)?.absoluteURL,
                      let format = validatedFormat(url, discID: discID), seen.insert(format).inserted else { return nil }
                let title = try link.text().trimmingCharacters(in: .whitespacesAndNewlines)
                return DownloadOption(title: title.isEmpty ? format : title, format: format, url: url)
            }
        }
    }

    static func validatedFormat(_ url: URL, discID: String) -> String? {
        guard url.scheme == "https", url.host == DizzyURL.site.host,
              url.port == nil || url.port == 443, url.user == nil, url.password == nil,
              url.path(percentEncoded: false) == "/albums/download/", url.fragment == nil,
              let items = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems else { return nil }
        let discs = items.filter { $0.name == "d" }
        let formats = items.filter { $0.name == "tp" }
        let signatures = items.filter { $0.name == "k" }
        guard discs.count == 1, discs[0].value == discID,
              formats.count == 1, let format = formats[0].value, ["128", "MP3", "FLAC"].contains(format),
              signatures.count == 1, let signature = signatures[0].value, !signature.isEmpty else { return nil }
        return format
    }
}
