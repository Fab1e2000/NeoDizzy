// 生成 App 图标：深色底上的一条黄色螺旋线。配色与 DizzyPalette 一致。
// 用法：swift scripts/generate-app-icon.swift
import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers

let size = 1024
let output = URL(fileURLWithPath: #filePath)
    .deletingLastPathComponent()
    .deletingLastPathComponent()
    .appending(path: "NeoDizzy/Resources/Assets.xcassets/AppIcon.appiconset/AppIcon-1024.png")

func color(_ hex: UInt32) -> CGColor {
    CGColor(
        srgbRed: CGFloat((hex >> 16) & 0xFF) / 255,
        green: CGFloat((hex >> 8) & 0xFF) / 255,
        blue: CGFloat(hex & 0xFF) / 255,
        alpha: 1
    )
}

// iOS 图标不能带透明通道。
let context = CGContext(
    data: nil, width: size, height: size, bitsPerComponent: 8, bytesPerRow: 0,
    space: CGColorSpace(name: CGColorSpace.sRGB)!,
    bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue
)!
context.setFillColor(color(0x1A1A1A))
context.fill(CGRect(x: 0, y: 0, width: size, height: size))

// 阿基米德螺线 r = a + bθ，从中心向外转两圈半。
let center = CGPoint(x: Double(size) / 2, y: Double(size) / 2)
let turns = 2.5
let innerRadius = 30.0
let outerRadius = 330.0
let steps = 900
let path = CGMutablePath()
for step in 0...steps {
    let progress = Double(step) / Double(steps)
    let angle = progress * turns * 2 * .pi
    let radius = innerRadius + (outerRadius - innerRadius) * progress
    let point = CGPoint(x: center.x + radius * cos(angle), y: center.y + radius * sin(angle))
    step == 0 ? path.move(to: point) : path.addLine(to: point)
}
// 螺线本身不对称，按外接框挪到正中，视觉上才居中。
let bounds = path.boundingBox
var shift = CGAffineTransform(translationX: center.x - bounds.midX, y: center.y - bounds.midY)
context.addPath(path.copy(using: &shift)!)
context.setStrokeColor(color(0xF0AD4E))
context.setLineWidth(56)
context.setLineCap(.round)
context.setLineJoin(.round)
context.strokePath()

let image = context.makeImage()!
let destination = CGImageDestinationCreateWithURL(output as CFURL, UTType.png.identifier as CFString, 1, nil)!
CGImageDestinationAddImage(destination, image, nil)
guard CGImageDestinationFinalize(destination) else { fatalError("写入失败：\(output.path)") }
print("已生成 \(output.path)")
