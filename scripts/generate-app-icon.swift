// 黑底金色 D：参考 NeoBili 的左下挤出字母轮廓，重新绘制 D 的几何结构。
// 同时输出可编辑 SVG、Icon Composer 图标与不带 alpha 的 1024px PNG。
// 用法：xcrun swift scripts/generate-app-icon.swift
import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers

let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
let assets = root.appending(path: "NeoDizzy/Resources/AppIcons/NeoDizzyIcon.icon/Assets")
let design = root.appending(path: "design")
try FileManager.default.createDirectory(at: assets, withIntermediateDirectories: true)
try FileManager.default.createDirectory(at: design, withIntermediateDirectories: true)

// Canvas coordinates use SVG's downward y axis. A circular right bowl keeps D legible at small sizes.
let extrusion = CGMutablePath()
extrusion.move(to: CGPoint(x: 362, y: 194)); extrusion.addLine(to: CGPoint(x: 600, y: 194))
extrusion.addCurve(to: CGPoint(x: 772.534, y: 610.534), control1: CGPoint(x: 817.38, y: 194), control2: CGPoint(x: 926.24, y: 456.83))
extrusion.addLine(to: CGPoint(x: 622.534, y: 760.534))
extrusion.addCurve(to: CGPoint(x: 450, y: 832), control1: CGPoint(x: 576.78, y: 806.29), control2: CGPoint(x: 514.72, y: 832))
extrusion.addLine(to: CGPoint(x: 212, y: 832)); extrusion.addLine(to: CGPoint(x: 212, y: 344)); extrusion.closeSubpath()
func bowl(left: CGFloat, top: CGFloat, stem: CGFloat, radius: CGFloat) -> CGPath {
    let p = CGMutablePath(); let k: CGFloat = 0.5522847498
    p.move(to: CGPoint(x: left, y: top)); p.addLine(to: CGPoint(x: stem, y: top))
    p.addCurve(to: CGPoint(x: stem + radius, y: top + radius), control1: CGPoint(x: stem + k * radius, y: top), control2: CGPoint(x: stem + radius, y: top + radius * (1-k)))
    p.addCurve(to: CGPoint(x: stem, y: top + 2 * radius), control1: CGPoint(x: stem + radius, y: top + radius * (1+k)), control2: CGPoint(x: stem + k * radius, y: top + 2 * radius))
    p.addLine(to: CGPoint(x: left, y: top + 2 * radius)); p.closeSubpath(); return p
}
let rim = bowl(left: 362, top: 194, stem: 600, radius: 244)
let face = bowl(left: 378, top: 210, stem: 600, radius: 228)
let counter = bowl(left: 498, top: 320, stem: 580, radius: 118)
func color(_ value: UInt32) -> CGColor {
    CGColor(srgbRed: CGFloat((value >> 16) & 255) / 255, green: CGFloat((value >> 8) & 255) / 255, blue: CGFloat(value & 255) / 255, alpha: 1)
}
func svgPath(_ path: CGPath) -> String {
    var text = ""
    path.applyWithBlock { pointer in
        let e = pointer.pointee
        func point(_ i: Int) -> String { String(format: "%.3f %.3f", Double(e.points[i].x), Double(e.points[i].y)) }
        switch e.type {
        case .moveToPoint: text += "M \(point(0)) "
        case .addLineToPoint: text += "L \(point(0)) "
        case .addCurveToPoint: text += "C \(point(0)) \(point(1)) \(point(2)) "
        case .closeSubpath: text += "Z "
        case .addQuadCurveToPoint: text += "Q \(point(0)) \(point(1)) "
        @unknown default: break
        }
    }
    return text
}
let paths: [(CGPath, UInt32)] = [(extrusion, 0x936022), (rim, 0xFFD58A), (face, 0xF0AD4E), (counter, 0x080808)]
let mark = "<g transform=\"translate(-16 0)\">" + paths.map { "<path d=\"\(svgPath($0.0))\" fill=\"#\(String(format: "%06X", $0.1))\"/>" }.joined() + "</g>"
let opening = "<svg xmlns=\"http://www.w3.org/2000/svg\" width=\"1024\" height=\"1024\" viewBox=\"0 0 1024 1024\">"
try (opening + mark + "</svg>\n").write(to: assets.appending(path: "Mark.svg"), atomically: true, encoding: .utf8)
try (opening + "<rect width=\"1024\" height=\"1024\" fill=\"#080808\"/>" + mark + "</svg>\n").write(to: design.appending(path: "AppIcon.svg"), atomically: true, encoding: .utf8)
let document: [String: Any] = ["fill": ["solid": "srgb:0.03137,0.03137,0.03137,1.00000"], "groups": [["layers": [["image-name": "Mark.svg", "name": "Gold D"]]]], "supported-platforms": ["squares": "shared"]]
try JSONSerialization.data(withJSONObject: document, options: [.prettyPrinted, .sortedKeys]).write(to: assets.deletingLastPathComponent().appending(path: "icon.json"))
let context = CGContext(data: nil, width: 1024, height: 1024, bitsPerComponent: 8, bytesPerRow: 0, space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue)!
context.setFillColor(color(0x080808)); context.fill(CGRect(x: 0, y: 0, width: 1024, height: 1024))
context.translateBy(x: -16, y: 1024); context.scaleBy(x: 1, y: -1)
for (path, fill) in paths { context.addPath(path); context.setFillColor(color(fill)); context.fillPath() }
let output = root.appending(path: "NeoDizzy/Resources/Assets.xcassets/AppIcon.appiconset/AppIcon-1024.png")
let destination = CGImageDestinationCreateWithURL(output as CFURL, UTType.png.identifier as CFString, 1, nil)!
CGImageDestinationAddImage(destination, context.makeImage()!, nil)
guard CGImageDestinationFinalize(destination) else { fatalError("图标写入失败") }
print("已生成黑底金色 D 图标、SVG 和 Icon Composer 文件")
