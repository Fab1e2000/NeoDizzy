import Foundation
import Testing

/// 读取 `Fixtures/` 里保存的真实页面和接口样本。
/// 样本删去了脚本、导航、页脚和其他用户的头像，解析用到的结构保持原样。
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
