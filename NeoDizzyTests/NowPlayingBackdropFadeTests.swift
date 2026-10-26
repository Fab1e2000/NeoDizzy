import Foundation
import UIKit
import Testing
@testable import NeoDizzy

@Suite @MainActor struct NowPlayingBackdropFadeTests {
    @Test func alignedTextTracksScrollButNotPopupTranslation() throws {
        let scene = try #require(UIApplication.shared.connectedScenes.first as? UIWindowScene)
        let window = UIWindow(windowScene: scene)
        window.rootViewController = UIViewController()
        window.makeKeyAndVisible()
        defer { window.isHidden = true; window.rootViewController = nil }
        let popup = UIView(frame: CGRect(x: 0, y: 0, width: 402, height: 874))
        window.rootViewController!.view.addSubview(popup)
        let anchor = NowPlayingBackdropAnchor()
        let background = NowPlayingBackdropAnchorView.AnchorView(anchor: anchor)
        background.frame = popup.bounds
        popup.addSubview(background)
        let scroll = UIScrollView(frame: popup.bounds)
        scroll.contentInsetAdjustmentBehavior = .never
        scroll.contentSize = CGSize(width: 402, height: 1800)
        popup.addSubview(scroll)
        let text = NowPlayingAlignedBackdrop.AlignedView(anchor: anchor)
        text.frame = CGRect(x: 32, y: 240, width: 300, height: 26)
        scroll.addSubview(text)
        window.layoutIfNeeded()
        text.align()
        let initial = text.imageView.frame
        #expect(initial == CGRect(x: -32, y: -240, width: 402, height: 874))
        popup.center.y += 120
        popup.transform = CGAffineTransform(scaleX: 0.92, y: 0.92)
        anchor.refresh()
        #expect(abs(text.imageView.frame.minY - initial.minY) < 0.01)
        #expect(abs(text.imageView.frame.width - initial.width) < 0.01)
        scroll.contentOffset.y = 100
        anchor.refresh()
        #expect(abs(text.imageView.frame.minY - (initial.minY + 100)) < 0.01)
        background.bounds.size.height = 800
        anchor.refresh()
        #expect(abs(text.imageView.frame.height - 800) < 0.01)
    }

    @Test func overlayFadeAndInterruptedSkipNeverExposeBlack() async throws {
        func swatch(_ color: UIColor) -> UIImage {
            UIGraphicsImageRenderer(size: CGSize(width: 2, height: 2)).image { context in
                color.setFill()
                context.fill(CGRect(x: 0, y: 0, width: 2, height: 2))
            }
        }
        let scene = try #require(UIApplication.shared.connectedScenes.first as? UIWindowScene)
        let window = UIWindow(windowScene: scene)
        let controller = UIViewController()
        controller.view.backgroundColor = .black
        window.rootViewController = controller
        window.makeKeyAndVisible()
        let view = NowPlayingBackdropImage.CrossfadeView()
        view.frame = CGRect(x: 40, y: 100, width: 64, height: 64)
        controller.view.addSubview(view)
        defer { view.stop(); window.isHidden = true; window.rootViewController = nil }
        window.layoutIfNeeded()
        view.setImage(swatch(.red), animated: false)
        view.setImage(swatch(.green), animated: true)
        for step in 0..<8 {
            try await Task.sleep(for: .milliseconds(100))
            let screenshot = UIGraphicsImageRenderer(bounds: view.bounds).image { _ in
                view.drawHierarchy(in: view.bounds, afterScreenUpdates: true)
            }
            let cgImage = try #require(screenshot.cgImage)
            var pixel: [UInt8] = [0, 0, 0, 0]
            pixel.withUnsafeMutableBytes { bytes in
                let context = CGContext(data: bytes.baseAddress, width: 1, height: 1,
                    bitsPerComponent: 8, bytesPerRow: 4,
                    space: CGColorSpace(name: CGColorSpace.sRGB)!,
                    bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
                context.draw(cgImage, in: CGRect(x: 0, y: 0, width: 1, height: 1))
            }
            // Red/green/blue and their opaque interpolations retain total RGB energy.
            #expect(Int(pixel[0]) + Int(pixel[1]) + Int(pixel[2]) >= 220)
            if step == 1 { view.setImage(swatch(.blue), animated: true) }
        }
        view.setImage(swatch(.white), animated: false)
        #expect(view.subviews.compactMap { $0 as? UIImageView }.first?.alpha == 1)
    }
}
