import Foundation
import CoreGraphics
import SwiftUI
import UIKit
import Testing
@testable import NeoDizzy

@Suite(.serialized)
struct AlbumBackdropTests {
    @MainActor @Test func emptyCollectionCanAppearAndDismissBeforeArtworkArrives() async throws {
        // Recent playback has no cover until its response arrives. Exercise this path
        // with the real SwiftUI task modifiers, including Release optimization.
        let controller = UIHostingController(rootView:
            AlbumDetailScrollView(artworkURL: nil) {
                AlbumHero(artworkURL: nil, title: "最近播放", metadata: "正在加载…") {
                    Text("网易云账号的最近播放记录")
                } actions: {
                    AlbumPlaybackActions(isEmpty: true) { _ in }
                }
            }
        )
        let scene = try #require(UIApplication.shared.connectedScenes.first as? UIWindowScene)
        let window = UIWindow(windowScene: scene)
        window.rootViewController = controller
        window.makeKeyAndVisible()
        defer { window.isHidden = true; window.rootViewController = nil }
        try await Task.sleep(for: .milliseconds(500))
        #expect(controller.view.window != nil)
    }

    @MainActor @Test(arguments: [false, true])
    func recentCollectionReceivesArtworkAfterAppearing(preloaded: Bool) async throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".png")
        let image = UIGraphicsImageRenderer(size: CGSize(width: 32, height: 32)).image { context in
            UIColor.blue.setFill()
            context.fill(CGRect(x: 0, y: 0, width: 32, height: 32))
        }
        try #require(image.pngData()).write(to: url)
        defer { try? FileManager.default.removeItem(at: url) }
        if preloaded { await AlbumArtworkPreload.prepare(url) }
        let controller = UIHostingController(rootView: RecentArtworkFixture(loadedURL: url))
        let scene = try #require(UIApplication.shared.connectedScenes.first as? UIWindowScene)
        let window = UIWindow(windowScene: scene)
        window.rootViewController = controller
        window.makeKeyAndVisible()
        defer { window.isHidden = true; window.rootViewController = nil }
        try await Task.sleep(for: .seconds(1))
        #expect(controller.view.window != nil)
    }

    @Test func decodingTheSamePaletteDoesNotRestartTheTransition() throws {
        let context = try #require(CGContext(data: nil, width: 1, height: 1, bitsPerComponent: 8,
                                            bytesPerRow: 4, space: CGColorSpaceCreateDeviceRGB(),
                                            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
        let first = try #require(context.makeImage())
        let second = try #require(context.makeImage())
        let color = SIMD3<Double>(0.2, 0.4, 0.6)
        let displayed = AlbumBackdrop(averageRGB: color, blurredImage: first)
        let redecoded = AlbumBackdrop(averageRGB: color, blurredImage: second)
        #expect(displayed.alreadyDisplays(redecoded))
        #expect(!AlbumBackdrop(averageRGB: color).alreadyDisplays(redecoded))
        #expect(!displayed.alreadyDisplays(AlbumBackdrop(averageRGB: SIMD3(repeating: 0.9))))
    }

    @Test func darkArtworkKeepsItsHueOnADarkBackground() {
        let backdrop = AlbumBackdrop(averageRGB: SIMD3(0.2, 0.4, 0.6))
        #expect(backdrop.prefersDarkAppearance)
        #expect(backdrop.backgroundRGB.z > backdrop.backgroundRGB.y)
        #expect(backdrop.backgroundRGB.y > backdrop.backgroundRGB.x)
        #expect(backdrop.backgroundRGB.z < 0.3)
    }

    @Test func brightArtworkUsesALightBackground() {
        let backdrop = AlbumBackdrop(averageRGB: SIMD3(1, 0.9, 0.1))
        #expect(!backdrop.prefersDarkAppearance)
        #expect(backdrop.backgroundRGB.x > 0.9)
        #expect(backdrop.backgroundRGB.z > 0.65)
    }

    @Test func paletteProvidesReadableTextAcrossSourceColors() {
        func linear(_ value: Double) -> Double {
            value <= 0.04045 ? value / 12.92 : pow((value + 0.055) / 1.055, 2.4)
        }
        for r in stride(from: 0.0, through: 1.0, by: 0.2) {
            for g in stride(from: 0.0, through: 1.0, by: 0.2) {
                for b in stride(from: 0.0, through: 1.0, by: 0.2) {
                    let backdrop = AlbumBackdrop(averageRGB: SIMD3(r, g, b))
                    let color = backdrop.backgroundRGB
                    let luminance = linear(color.x) * 0.2126 + linear(color.y) * 0.7152 + linear(color.z) * 0.0722
                    let contrast = backdrop.prefersDarkAppearance ? 1.05 / (luminance + 0.05) : (luminance + 0.05) / 0.05
                    #expect(contrast >= 4.5)
                }
            }
        }
    }
}

private struct RecentArtworkFixture: View {
    let loadedURL: URL
    @State private var url: URL?
    var body: some View {
        AlbumDetailScrollView(artworkURL: url) {
            AlbumHero(artworkURL: url, title: "最近播放", metadata: "测试") {
                Text("最近播放")
            } actions: {
                AlbumPlaybackActions(isEmpty: true) { _ in }
            }
        }
        .task {
            try? await Task.sleep(for: .milliseconds(50))
            url = loadedURL
        }
    }
}
