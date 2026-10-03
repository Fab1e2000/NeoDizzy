import Foundation
import ImageIO
import UniformTypeIdentifiers

/// 封面图片统一转成最长边不超过 2048 像素的 PNG；只用 ImageIO，iOS 与 macOS 共用。
nonisolated enum CoverImageEncoder {
    static let maximumBytes = 20 * 1024 * 1024

    /// 原图超过 20 MB、无法解码或无法编码时返回 nil。
    static func png(from data: Data) -> Data? {
        guard data.count <= maximumBytes,
              let source = CGImageSourceCreateWithData(data as CFData, nil),
              let thumbnail = CGImageSourceCreateThumbnailAtIndex(source, 0, [
                kCGImageSourceCreateThumbnailFromImageAlways: true,
                kCGImageSourceCreateThumbnailWithTransform: true,
                kCGImageSourceThumbnailMaxPixelSize: 2048
              ] as CFDictionary) else { return nil }
        let output = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(output, UTType.png.identifier as CFString, 1, nil) else { return nil }
        CGImageDestinationAddImage(destination, thumbnail, nil)
        guard CGImageDestinationFinalize(destination) else { return nil }
        return output as Data
    }
}
