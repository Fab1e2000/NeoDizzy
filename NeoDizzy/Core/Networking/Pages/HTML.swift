import Foundation
import SwiftSoup

/// 各页面解析器共用的工具。网页是 Django 服务端渲染的 Bootstrap 页面，
/// 链接、图片和价格的写法在不同页面之间基本一致。
nonisolated enum HTML {
    /// 解析整页。网站出错时也返回 200，页面标题是「出错了！」，这里统一当作解析失败。
    static func document(_ html: String, page: String) throws -> Document {
        let document: Document
        do {
            document = try SwiftSoup.parse(html, DizzyURL.site.absoluteString)
        } catch {
            throw DizzyError.parsing(page)
        }
        if (try? document.title())?.hasPrefix("出错了") == true {
            throw DizzyError.parsing(page)
        }
        return document
    }

    /// 把 SwiftSoup 的异常统一换成 `DizzyError.parsing`。
    static func parsing<T>(_ page: String, _ work: () throws -> T) throws -> T {
        do {
            return try work()
        } catch let error as DizzyError {
            throw error
        } catch {
            throw DizzyError.parsing(page)
        }
    }

    // MARK: 链接

    /// `/d/obs-CD06BP`、`/d/fx4/` → 专辑 ID。
    static func discID(fromHref href: String) -> String? {
        segment(after: "/d/", in: href)
    }

    /// `/l/obscuRE TRAX`、`/l/%E9%9B%AA…` → 社团名。
    static func labelName(fromHref href: String) -> String? {
        segment(after: "/l/", in: href)?.removingPercentEncoding
    }

    /// `/pack/?pk=obs-PACK01` → pack ID。
    static func packID(fromHref href: String) -> String? {
        queryValue("pk", in: href)
    }

    /// 从链接里取查询参数，网站的链接常带未转义的中文，所以不经过 URLComponents。
    static func queryValue(_ name: String, in href: String) -> String? {
        guard let query = href.split(separator: "?", maxSplits: 1).dropFirst().first else { return nil }
        for pair in query.split(separator: "&") {
            let parts = pair.split(separator: "=", maxSplits: 1)
            if parts.count == 2, parts[0] == name {
                let value = String(parts[1])
                return value.removingPercentEncoding ?? value
            }
        }
        return nil
    }

    private static func segment(after prefix: String, in href: String) -> String? {
        guard let range = href.range(of: prefix) else { return nil }
        let rest = href[range.upperBound...]
        let end = rest.firstIndex(where: { "/?#".contains($0) }) ?? rest.endIndex
        let value = String(rest[..<end])
        return value.isEmpty ? nil : value
    }

    // MARK: 内容

    /// 懒加载图片的真实地址在 `data-src`，`src` 是占位图；没有 `data-src` 时才用 `src`。
    static func imageURL(_ image: Element?) -> URL? {
        guard let image else { return nil }
        for attribute in ["data-src", "src"] {
            let value = (try? image.attr(attribute)) ?? ""
            if let url = DizzyURL.image(value), !DizzyURL.isPlaceholderImage(url) {
                return url
            }
        }
        return nil
    }

    /// 保留 `<br>` 换行的纯文本。HTML 源码里的换行只是空白，不算换行。
    static func multilineText(_ element: Element?) -> String {
        guard let element else { return "" }
        var output = ""
        func walk(_ node: Node) {
            if let text = node as? TextNode {
                output += text.getWholeText().replacing(#/\s+/#, with: " ")
            } else if let element = node as? Element {
                if element.tagName() == "br" {
                    output += "\n"
                    return
                }
                element.getChildNodes().forEach(walk)
                if ["p", "div", "h1", "h2", "h3", "h4", "li"].contains(element.tagName()) {
                    output += "\n"
                }
            }
        }
        element.getChildNodes().forEach(walk)
        return output
            .split(separator: "\n", omittingEmptySubsequences: false)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .joined(separator: "\n")
            .replacing(#/\n{3,}/#, with: "\n\n")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// 第一个数字，例如 `¥ 45.0` → 45、`使用支付宝支付: 84.0元` → 84。
    static func number(in text: String?) -> Double? {
        guard let text, let match = text.firstMatch(of: #/\d+(?:\.\d+)?/#) else { return nil }
        return Double(match.output)
    }

    /// 卡片上的价格：`免费`、`¥ 45.0`，或限时优惠 `<del>¥ 40.0</del> 18.0`。
    static func price(_ element: Element?) -> PriceTag? {
        guard let element, let text = try? element.text() else { return nil }
        if text.contains("免费") { return .free }
        if text.contains("兑换") { return .redeem }
        if let original = try? element.select("del").first() {
            guard let was = number(in: try? original.text()),
                  let now = number(in: element.ownText()) else { return nil }
            return .deal(original: was, current: now)
        }
        return number(in: text).map(PriceTag.price)
    }

    /// 列表页底部有「下一页」按钮时还有下一页。
    static func hasNextPage(_ document: Document) -> Bool {
        let links = (try? document.select("nav a").array()) ?? []
        return links.contains { ((try? $0.text()) ?? "").contains("下一页") }
    }

    /// 首页和社团页里的 pack 卡片。
    static func packCard(_ card: Element) -> PackSummary? {
        guard let link = try? card.select("a[href*=pack/?pk=]").first(),
              let id = packID(fromHref: (try? link.attr("href")) ?? "") else { return nil }
        let title = (try? card.select("h4 a").first()?.text()) ?? nil
        let label = (try? card.select("h3 a").first()?.text()) ?? nil
        return PackSummary(
            id: id,
            title: title ?? id,
            coverURL: imageURL(try? card.select("img").first()),
            labelName: label.map(stripAt),
            price: number(in: (try? card.select(".badge").first()?.text()) ?? nil)
        )
    }

    /// 卡片上的社团名写作 `@ obscuRE TRAX`。
    static func stripAt(_ text: String) -> String {
        var name = text.trimmingCharacters(in: .whitespaces)
        if name.hasPrefix("@") { name.removeFirst() }
        return name.trimmingCharacters(in: .whitespaces)
    }
}
