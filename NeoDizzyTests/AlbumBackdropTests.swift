import Testing
@testable import NeoDizzy

struct AlbumBackdropTests {
    private typealias RGB = SIMD3<Double>

    /// 一张 `size` 见方的不透明图，`color(x, y)` 给出每个像素的 0–255 颜色。
    private func image(size: Int = 100, color: (Int, Int) -> SIMD3<UInt8>) -> [UInt8] {
        var pixels: [UInt8] = []
        for y in 0..<size {
            for x in 0..<size {
                let value = color(x, y)
                pixels += [value.x, value.y, value.z, 255]
            }
        }
        return pixels
    }

    private func isClose(_ lhs: RGB, _ rhs: RGB, tolerance: Double = 0.02) -> Bool {
        ((lhs - rhs) * (lhs - rhs)).sum() < tolerance * tolerance * 3
    }


    @Test func picksEdgeColorRatherThanCenter() {
        // 白底中间一大块黑：平均色是灰，边缘是白。
        let pixels = image { x, y in (20..<80).contains(x) && (20..<80).contains(y) ? [0, 0, 0] : [255, 255, 255] }
        let edge = AlbumBackdrop.edgeColor(pixels: pixels, width: 100, height: 100)
        #expect(isClose(edge, RGB(repeating: 1)))
    }

    @Test func mostCommonEdgeColorWinsOverMixing() {
        // 外圈大半是红，上边一条蓝：取红，不混成紫。
        let pixels = image { _, y in y < 3 ? [0, 0, 255] : [220, 30, 30] }
        let edge = AlbumBackdrop.edgeColor(pixels: pixels, width: 100, height: 100)
        #expect(isClose(edge, RGB(220, 30, 30) / 255))
    }

    @Test func busyEdgeFallsBackToWholeCoverDominantColor() {
        // 外圈每个像素颜色都不同，中间是一整块绿。
        let pixels = image { x, y in
            (8..<92).contains(x) && (8..<92).contains(y)
                ? [40, 160, 70]
                : [UInt8((x * 37 + y * 11) % 256), UInt8((x * 13 + y * 71) % 256), UInt8((x * 59 + y * 29) % 256)]
        }
        let edge = AlbumBackdrop.edgeColor(pixels: pixels, width: 100, height: 100)
        #expect(isClose(edge, RGB(40, 160, 70) / 255))
    }

    @Test func ignoresTransparentPixels() {
        var pixels = image { x, _ in x < 50 ? [255, 255, 255] : [30, 60, 200] }
        for index in stride(from: 0, to: pixels.count, by: 4) where (index / 4) % 100 < 50 {
            pixels[index..<index + 4] = [0, 0, 0, 0]
        }
        let edge = AlbumBackdrop.edgeColor(pixels: pixels, width: 100, height: 100)
        #expect(isClose(edge, RGB(30, 60, 200) / 255))
    }

    @Test func backgroundIsEdgeColorUnchanged() {
        let pixels = image { _, _ in [230, 150, 140] }
        let edge = AlbumBackdrop.edgeColor(pixels: pixels, width: 100, height: 100)
        #expect(isClose(AlbumBackdrop(edgeRGB: edge).edgeRGB, RGB(230, 150, 140) / 255))
    }

    @Test func textColorFollowsBackgroundContrast() {
        // 浅色、亮黄、浅粉配黑字；深蓝、深灰、纯红配白字。
        for light in [RGB(1, 1, 1), RGB(1, 0.9, 0.1), RGB(0.9, 0.6, 0.55)] {
            #expect(!AlbumBackdrop(edgeRGB: light).prefersDarkAppearance)
        }
        for dark in [RGB(0, 0, 0), RGB(0.1, 0.15, 0.4), RGB(0.3, 0.3, 0.3), RGB(0.8, 0.1, 0.1)] {
            #expect(AlbumBackdrop(edgeRGB: dark).prefersDarkAppearance)
        }
    }
}
