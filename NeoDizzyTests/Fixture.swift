import Foundation
import Testing

/// 读取 `Fixtures/` 中的页面、接口和压缩包样本。
/// 既有网页样本去掉了无关个人信息；download-* 为人工构造的解析及安全回归样本，不含音乐内容。
enum Fixture {
    private final class BundleToken {}

    static func data(_ name: String) throws -> Data {
        let bundle = Bundle(for: BundleToken.self)
        let url = bundle.url(forResource: name, withExtension: nil)
            ?? bundle.url(forResource: name, withExtension: nil, subdirectory: "Fixtures")
        return try Data(contentsOf: #require(url, "缺少样本 \(name)"))
    }

    static func text(_ name: String) throws -> String {
        String(decoding: try data(name), as: UTF8.self)
    }
}
