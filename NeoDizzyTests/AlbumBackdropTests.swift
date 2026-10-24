import Foundation
import CoreGraphics
import SwiftUI
import UIKit
import Testing
@testable import NeoDizzy

@Suite(.serialized)
struct AlbumBackdropTests {
    @MainActor @Test func preparedArtworkProvidesTheInitialPaletteSynchronously() async throws {
        let url = try blueArtworkFile()
        defer { try? FileManager.default.removeItem(at: url) }
        #expect(!AlbumArtworkPreload.hasPreparedBackdrop(for: url))

        await AlbumArtworkPreload.prepareBackdrop(url)

        #expect(AlbumArtworkPreload.hasPreparedBackdrop(for: url))
        let route = artworkTestRoute("prepared")
        let navigation = AlbumNavigationPreparation()
        #expect(navigation.begin(route, artworkURL: url) == route)
        #expect(navigation.request == nil)
        // The destination reads its final palette during initialization, without load().
        let model = AlbumBackdropModel(url: url)
        let backdrop = try #require(model.backdrop)
        #expect(backdrop.averageRGB.z > 0.9)
        #expect(backdrop.averageRGB.x < 0.1)
        #expect(backdrop.averageRGB.y < 0.1)
        #expect(backdrop.blurredImage != nil)
        #expect(backdrop.backgroundRGB.min() > 0.85)
    }

    @MainActor @Test func navigationWaitsForArtworkAndIgnoresDuplicateTaps() async throws {
        let url = try blueArtworkFile()
        defer { try? FileManager.default.removeItem(at: url) }
        let route = artworkTestRoute("pending")
        let navigation = AlbumNavigationPreparation()
        #expect(navigation.begin(route, artworkURL: url) == nil)
        let pending = try #require(navigation.request)
        let gate = ArtworkPreparationGate()
        var openedRoute: AppRoute?
        let work = Task {
            openedRoute = await navigation.finish(pending) { url in
                await gate.wait()
                await AlbumArtworkPreload.prepareBackdrop(url)
            }
        }
        await gate.waitUntilStarted()
        #expect(openedRoute == nil)
        #expect(!AlbumArtworkPreload.hasPreparedBackdrop(for: url))
        #expect(navigation.begin(route, artworkURL: url) == nil)
        #expect(navigation.request == pending)

        gate.release()
        await work.value
        #expect(openedRoute == route)
        #expect(navigation.request == nil)
        #expect(AlbumBackdropModel(url: url).backdrop?.blurredImage != nil)
    }

    @MainActor @Test(arguments: [false, true])
    func cancelledArtworkPreparationCannotNavigate(cancelTask: Bool) async throws {
        let navigation = AlbumNavigationPreparation()
        let route = artworkTestRoute("cancelled")
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        #expect(navigation.begin(route, artworkURL: url, isReady: { _ in false }) == nil)
        let pending = try #require(navigation.request)
        let gate = ArtworkPreparationGate()
        var openedRoute: AppRoute?
        let work = Task { openedRoute = await navigation.finish(pending) { _ in await gate.wait() } }
        await gate.waitUntilStarted()

        if cancelTask { work.cancel() } else { navigation.cancel() }
        gate.release()
        await work.value
        #expect(openedRoute == nil)
        navigation.cancel()
        #expect(navigation.request == nil)
    }

    @MainActor @Test func replacedArtworkPreparationCannotNavigateOrClearTheNewRequest() async throws {
        let navigation = AlbumNavigationPreparation()
        let oldRoute = artworkTestRoute("old")
        let newRoute = artworkTestRoute("new")
        let oldURL = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let newURL = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        #expect(navigation.begin(oldRoute, artworkURL: oldURL, isReady: { _ in false }) == nil)
        let oldRequest = try #require(navigation.request)
        let gate = ArtworkPreparationGate()
        var openedRoute: AppRoute?
        let oldWork = Task { openedRoute = await navigation.finish(oldRequest) { _ in await gate.wait() } }
        await gate.waitUntilStarted()

        navigation.cancel()
        #expect(navigation.begin(newRoute, artworkURL: newURL, isReady: { _ in false }) == nil)
        let newRequest = try #require(navigation.request)
        gate.release()
        await oldWork.value
        #expect(openedRoute == nil)
        #expect(navigation.request == newRequest)
        let result = await navigation.finish(newRequest) { _ in }
        #expect(result == newRoute)
        #expect(navigation.request == nil)
    }

    @MainActor @Test func absentOrInvalidArtworkStillAllowsNavigation() async throws {
        let navigation = AlbumNavigationPreparation()
        let route = artworkTestRoute("unavailable-artwork")
        #expect(navigation.begin(route, artworkURL: nil) == route)
        #expect(navigation.request == nil)

        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".png")
        try Data("invalid image".utf8).write(to: url)
        defer { try? FileManager.default.removeItem(at: url) }
        #expect(navigation.begin(route, artworkURL: url) == nil)
        let pending = try #require(navigation.request)
        let result = await navigation.finish(pending)
        #expect(result == route)
        #expect(navigation.request == nil)
        #expect(!AlbumArtworkPreload.hasPreparedBackdrop(for: url))
        #expect(AlbumBackdropModel(url: url).backdrop == nil)
    }

    @MainActor @Test func artworkArrivingAfterInitializationPublishesItsPalette() async throws {
        let url = try blueArtworkFile()
        defer { try? FileManager.default.removeItem(at: url) }
        let model = AlbumBackdropModel(url: nil)
        #expect(model.backdrop == nil)

        await model.load(url)

        let backdrop = try #require(model.backdrop)
        #expect(backdrop.averageRGB.z > 0.9)
        #expect(backdrop.blurredImage != nil)
        await model.load(nil)
        #expect(model.backdrop == backdrop)
    }

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

    @Test func darkArtworkKeepsItsHueOnALightBackground() {
        let backdrop = AlbumBackdrop(averageRGB: SIMD3(0.2, 0.4, 0.6))
        #expect(backdrop.backgroundRGB.min() > 0.85)
        #expect(backdrop.backgroundRGB.z > backdrop.backgroundRGB.y)
        #expect(backdrop.backgroundRGB.y > backdrop.backgroundRGB.x)
        #expect(backdrop.backgroundRGB.z > 0.9)
    }

    @Test func brightArtworkUsesALightBackground() {
        let backdrop = AlbumBackdrop(averageRGB: SIMD3(1, 0.9, 0.1))
        #expect(backdrop.backgroundRGB.min() > 0.85)
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
                    let contrast = (luminance + 0.05) / 0.05
                    #expect(contrast >= 4.5)
                }
            }
        }
    }
}

@MainActor private func blueArtworkFile() throws -> URL {
    let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".png")
    let image = UIGraphicsImageRenderer(size: CGSize(width: 32, height: 32)).image { context in
        UIColor.blue.setFill()
        context.fill(CGRect(x: 0, y: 0, width: 32, height: 32))
    }
    try #require(image.pngData()).write(to: url)
    return url
}

private func artworkTestRoute(_ id: String) -> AppRoute {
    AppRoute(moduleID: ModuleID(rawValue: "artwork-test"), destination: id, title: id)
}

@MainActor private final class ArtworkPreparationGate {
    private var started = false
    private var startWaiter: CheckedContinuation<Void, Never>?
    private var completion: CheckedContinuation<Void, Never>?

    func wait() async {
        started = true
        startWaiter?.resume()
        startWaiter = nil
        await withCheckedContinuation { completion = $0 }
    }

    func waitUntilStarted() async {
        if started { return }
        await withCheckedContinuation { startWaiter = $0 }
    }

    func release() {
        completion?.resume()
        completion = nil
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
