import SwiftUI
#if canImport(UIKit)
import UIKit
#else
import AppKit
#endif

/// 歌词行高：iOS 用 UIFont.lineHeight，macOS 用 NSLayoutManager 的默认行高，两者都对应系统粗体。
enum LyricsFontMetrics {
    static func boldLineHeight(size: CGFloat) -> CGFloat {
        #if canImport(UIKit)
        UIFont.systemFont(ofSize: size, weight: .bold).lineHeight
        #else
        NSLayoutManager().defaultLineHeight(for: .systemFont(ofSize: size, weight: .bold))
        #endif
    }
}
