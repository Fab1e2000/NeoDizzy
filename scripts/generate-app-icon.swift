// 挤出的 D：沿用 NeoBili 图标的做法，白底上只用一种主题色——挤出的侧面和字母的细边
// 是主题色，字母正面镂空露出底色，字腔露出后面的主题色。深色图标由系统自动生成
// （底色变黑、主题色保留），不另画一版。
// 按 AppTheme.swift 里的主题表为每个主题输出一个 Icon Composer 图标：默认主题是主图标，
// 其余是 iOS 的备选图标。同时输出可编辑 SVG、不带 alpha 的 1024px PNG（README 用），
// 以及用 ictool 渲染的 Mac Dock 图标（Mac 没有备选图标接口，运行时换 Dock 图片）。
// 用法：xcrun swift scripts/generate-app-icon.swift
import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers

let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
let iconsFolder = root.appending(path: "NeoDizzy/Resources/AppIcons")
let dockFolder = root.appending(path: "NeoDizzyMac/Resources/DockIcons.xcassets")
let design = root.appending(path: "design")
let ictool = "/Applications/Xcode.app/Contents/Applications/Icon Composer.app/Contents/Executables/ictool"
let fileManager = FileManager.default
try fileManager.createDirectory(at: design, withIntermediateDirectories: true)

// MARK: 主题表

struct Theme { let id: String; let name: String; let dark: UInt32; let light: UInt32 }
let themeSource = try String(contentsOf: root.appending(path: "NeoDizzy/Core/UI/AppTheme.swift"), encoding: .utf8)
let themePattern = try NSRegularExpression(pattern: #"\.init\(id: "([^"]+)", name: "([^"]+)", dark: 0x([0-9A-F]{6}), light: 0x([0-9A-F]{6})\)"#)
let themes: [Theme] = themePattern.matches(in: themeSource, range: NSRange(themeSource.startIndex..., in: themeSource)).map { match in
    func group(_ i: Int) -> String { String(themeSource[Range(match.range(at: i), in: themeSource)!]) }
    return Theme(id: group(1), name: group(2), dark: UInt32(group(3), radix: 16)!, light: UInt32(group(4), radix: 16)!)
}
let defaultPattern = try NSRegularExpression(pattern: #"static let defaultID = "([^"]+)""#)
guard let defaultMatch = defaultPattern.firstMatch(in: themeSource, range: NSRange(themeSource.startIndex..., in: themeSource)),
      !themes.isEmpty else {
    fatalError("没有从 AppTheme.swift 读到主题表")
}
let defaultID = String(themeSource[Range(defaultMatch.range(at: 1), in: themeSource)!])

// MARK: 字形

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

// MARK: 配色

/// 按比例混入另一种颜色：混白得到受光的边，混黑得到挤出的侧面。
func mix(_ a: UInt32, _ b: UInt32, _ amount: Double) -> UInt32 {
    func channel(_ shift: UInt32) -> UInt32 {
        let x = Double((a >> shift) & 255), y = Double((b >> shift) & 255)
        return UInt32((x + (y - x) * amount).rounded()) << shift
    }
    return channel(16) | channel(8) | channel(0)
}
/// 图标用主题深浅两档的中间色：白底上不发灰，深色图标里也不发暗。
func iconColor(_ theme: Theme) -> UInt32 { mix(theme.dark, theme.light, 0.5) }
func hex(_ value: UInt32) -> String { String(format: "#%06X", value) }

let opening = "<svg xmlns=\"http://www.w3.org/2000/svg\" width=\"1024\" height=\"1024\" viewBox=\"0 0 1024 1024\">"
/// 奇偶填充：挤出轮廓减去字母正面，再补回字腔。
let markPath: CGPath = {
    let path = CGMutablePath()
    path.addPath(extrusion); path.addPath(face); path.addPath(counter)
    return path
}()
func mark(_ fill: UInt32) -> String {
    "<g transform=\"translate(-16 0)\"><path d=\"\(svgPath(markPath))\" fill-rule=\"evenodd\" fill=\"\(hex(fill))\"/></g>"
}

// MARK: 输出

func run(_ arguments: [String]) throws {
    let process = Process()
    process.executableURL = URL(fileURLWithPath: ictool)
    process.arguments = arguments
    process.standardOutput = FileHandle.nullDevice
    try process.run(); process.waitUntilExit()
    guard process.terminationStatus == 0 else { fatalError("ictool 失败：\(arguments)") }
}
func writeJSON(_ object: Any, to url: URL) throws {
    try JSONSerialization.data(withJSONObject: object, options: [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]).write(to: url)
}

// 先清掉旧主题留下的图标，避免删掉的主题仍被打包。
for url in try fileManager.contentsOfDirectory(at: iconsFolder, includingPropertiesForKeys: nil) where url.pathExtension == "icon" {
    try fileManager.removeItem(at: url)
}
try? fileManager.removeItem(at: dockFolder)
try fileManager.createDirectory(at: dockFolder, withIntermediateDirectories: true)
try writeJSON(["info": ["author": "xcode", "version": 1]], to: dockFolder.appending(path: "Contents.json"))

for theme in themes {
    let fill = iconColor(theme)
    let iconName = theme.id == defaultID ? "NeoDizzyIcon" : "NeoDizzyIcon-\(theme.id)"
    let icon = iconsFolder.appending(path: "\(iconName).icon")
    let assets = icon.appending(path: "Assets")
    try fileManager.createDirectory(at: assets, withIntermediateDirectories: true)
    try (opening + mark(fill) + "</svg>\n").write(to: assets.appending(path: "Mark.svg"), atomically: true, encoding: .utf8)
    let document: [String: Any] = [
        "fill": ["solid": "srgb:1.00000,1.00000,1.00000,1.00000"],
        "groups": [["layers": [["image-name": "Mark.svg", "name": "\(theme.name) D"]]]],
        "supported-platforms": ["squares": "shared"],
    ]
    try writeJSON(document, to: icon.appending(path: "icon.json"))

    // Mac Dock：按外观各渲染一张，带系统的 Liquid Glass 质感和圆角。
    for (appearance, rendition) in [("light", "Default"), ("dark", "Dark")] {
        let imageset = dockFolder.appending(path: "DockIcon-\(theme.id)-\(appearance).imageset")
        try fileManager.createDirectory(at: imageset, withIntermediateDirectories: true)
        try run([icon.path, "--export-image", "--output-file", imageset.appending(path: "icon.png").path,
                 "--platform", "macOS", "--rendition", rendition, "--width", "512", "--height", "512", "--scale", "1"])
        try writeJSON(["images": [["filename": "icon.png", "idiom": "universal"]], "info": ["author": "xcode", "version": 1]],
                      to: imageset.appending(path: "Contents.json"))
    }

    guard theme.id == defaultID else { continue }
    try (opening + "<rect width=\"1024\" height=\"1024\" fill=\"#FFFFFF\"/>" + mark(fill) + "</svg>\n")
        .write(to: design.appending(path: "AppIcon.svg"), atomically: true, encoding: .utf8)
    let context = CGContext(data: nil, width: 1024, height: 1024, bitsPerComponent: 8, bytesPerRow: 0, space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue)!
    context.setFillColor(color(0xFFFFFF)); context.fill(CGRect(x: 0, y: 0, width: 1024, height: 1024))
    context.translateBy(x: -16, y: 1024); context.scaleBy(x: 1, y: -1)
    context.addPath(markPath); context.setFillColor(color(fill)); context.fillPath(using: .evenOdd)
    let output = root.appending(path: "NeoDizzy/Resources/Assets.xcassets/AppIcon.appiconset/AppIcon-1024.png")
    let destination = CGImageDestinationCreateWithURL(output as CFURL, UTType.png.identifier as CFString, 1, nil)!
    CGImageDestinationAddImage(destination, context.makeImage()!, nil)
    guard CGImageDestinationFinalize(destination) else { fatalError("图标写入失败") }
}

let alternates = themes.filter { $0.id != defaultID }.map { "NeoDizzyIcon-\($0.id)" }.joined(separator: " ")
print("已生成 \(themes.count) 个主题的深浅双版图标与 Mac Dock 图标")
print("project.yml 的 ASSETCATALOG_COMPILER_ALTERNATE_APPICON_NAMES 应为：\(alternates)")
