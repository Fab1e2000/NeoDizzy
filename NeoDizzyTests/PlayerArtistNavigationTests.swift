import SwiftUI
import Testing
import UIKit
import MediaPlayer
@testable import NeoDizzy

@MainActor struct PlayerArtistNavigationTests {
    @Test func dispatchesToOwnerAndKeepsLocalArtistsIndependent() async throws {
        let first = ArtistFixtureModule("first")
        let second = ArtistFixtureModule("second")
        let registry = try ModuleRegistry([first, second])
        let route = AppRoute(moduleID: second.descriptor.id, destination: "artist-7", title: "Artist")
        second.resolve = { [.init(name: "Artist", route: route)] }
        let result = try await registry.artistDestinations(for: track(provider: "second"))
        #expect(result.map(\.route) == [route])
        #expect(first.requests == 0 && second.requests == 1)
        let local = Track(discID: "", number: "1", title: "Song", artists: "Local Artist", albumTitle: "", coverURL: nil,
                          localSource: .init(albumID: "local", trackID: "one"))
        #expect(try await registry.artistDestinations(for: local).first?.route == .libraryArtist("Local Artist", filter: .all))
        registry.remove(second.descriptor.id)
        await #expect(throws: ModuleCapabilityError.self) { try await registry.artistDestinations(for: track(provider: "second")) }
        #expect(first.requests == 0)
    }

    @Test func failureIsReportedWithoutSubstitutingAnotherSource() async throws {
        let owner = ArtistFixtureModule("provider")
        owner.resolve = { throw ArtistFixtureError.unavailable }
        let registry = try ModuleRegistry([owner])
        await #expect(throws: ArtistFixtureError.self) { try await registry.artistDestinations(for: track(provider: "provider")) }
    }

    @Test func removedProviderCannotPublishLateArtistDestinations() async throws {
        let owner = ArtistFixtureModule("provider")
        let registry = try ModuleRegistry([owner])
        var resume: CheckedContinuation<Void, Never>?
        owner.resolve = {
            await withCheckedContinuation { resume = $0 }
            return [.init(name: "Stale", route: AppRoute(moduleID: owner.descriptor.id, destination: "stale", title: "Stale"))]
        }
        let request = Task { try await registry.artistDestinations(for: track(provider: "provider")) }
        while resume == nil { await Task.yield() }
        registry.remove(owner.descriptor.id)
        resume?.resume()
        await #expect(throws: CancellationError.self) { try await request.value }
    }

    @Test func artistMenuUsesLocalNamesWithoutLoading() throws {
        let owner = ArtistFixtureModule("provider")
        let registry = try ModuleRegistry([owner])
        let menu = PlayerArtistMenuController()
        var opened: [AppRoute] = []
        menu.bind(track: track(provider: "provider", artists: "First / Second"), modules: registry, open: { opened.append($0) })
        let items = try #require(menu.menu()).children
        #expect(items.map(\.title) == ["前往First", "前往Second"])
        let more = try #require(menu.action(for: UIButton()) as? UIMenu)
        #expect(more.children.count == 2)
        #expect(menu.destinations().map(\.route.moduleID) == [.inlinePage, .inlinePage])
        #expect(owner.requests == 0)
        #expect(opened.isEmpty)
    }

    @Test func singleArtistOpensDirectlyAndLocalTracksUseLibrary() throws {
        let registry = try ModuleRegistry([ArtistFixtureModule("provider")])
        let menu = PlayerArtistMenuController()
        var opened: [AppRoute] = []
        menu.bind(track: track(provider: "provider"), modules: registry, open: { opened.append($0) })
        #expect(menu.menu() == nil)
        #expect(menu.action(for: UIButton()) is UIAction)
        menu.openSingle()
        #expect(opened.map(\.title) == ["Artist"])
        let local = Track(discID: "", number: "1", title: "Song", artists: "Local Artist", albumTitle: "", coverURL: nil,
                          localSource: .init(albumID: "local", trackID: "one"))
        menu.bind(track: local, modules: registry, open: { opened.append($0) })
        #expect(menu.destinations().first?.route == .libraryArtist("Local Artist", filter: .all))
    }

    @Test func singleDestinationSourceSkipsTheArtistSplit() throws {
        let owner = ArtistFixtureModule("provider")
        owner.artistNavigation = .single
        let registry = try ModuleRegistry([owner])
        let menu = PlayerArtistMenuController()
        menu.bind(track: track(provider: "provider", artists: "First / Second"), modules: registry, open: { _ in })
        #expect(menu.destinations().map(\.name) == ["First / Second"])
        #expect(menu.menu() == nil)
        #expect(owner.requests == 0)
    }

    @Test func artistPageMatchesByNameThenPositionThenSingleResult() {
        let a = AppRoute(moduleID: ModuleID(rawValue: "p"), destination: "a", title: "A")
        let b = AppRoute(moduleID: ModuleID(rawValue: "p"), destination: "b", title: "B")
        let both = [PlayerArtistDestination(name: "Alpha", route: a), PlayerArtistDestination(name: "Beta", route: b)]
        #expect(PlayerArtistPage.match(name: " beta ", index: 0, count: 2, in: both) == b)
        #expect(PlayerArtistPage.match(name: "Other", index: 1, count: 2, in: both) == b)
        #expect(PlayerArtistPage.match(name: "Other", index: 0, count: 3, in: [both[0]]) == a)
        #expect(PlayerArtistPage.match(name: "Other", index: 0, count: 3, in: both) == nil)
    }

    @Test func nativeArtistMenuDoesNotExpandTheQueueHeaderVertically() {
        let controller = UIHostingController(rootView: NowPlayingArtistButton(track: track(provider: "provider")))
        let size = controller.sizeThatFits(in: CGSize(width: 215, height: 700))
        #expect(size.height == 26)
        #expect(size.width <= 215)
    }

    @Test func systemVolumeThumbStaysInvisibleInNormalAndPressedStates() throws {
        let volume = AlignedSystemVolumeView(frame: CGRect(x: 0, y: 0, width: 288, height: 44))
        volume.layoutIfNeeded()
        for state: UIControl.State in [.normal, .highlighted, .disabled, .selected] {
            let image = try #require(volume.volumeThumbImage(for: state))
            let cgImage = try #require(image.cgImage)
            var pixel = [UInt8](repeating: 255, count: 4)
            let context = try #require(CGContext(data: &pixel, width: 1, height: 1, bitsPerComponent: 8,
                                               bytesPerRow: 4, space: CGColorSpaceCreateDeviceRGB(),
                                               bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
            context.clear(CGRect(x: 0, y: 0, width: 1, height: 1))
            context.draw(cgImage, in: CGRect(x: 0, y: 0, width: 1, height: 1))
            #expect(pixel[3] == 0)
        }
    }

    private func track(provider: String, artists: String = "Artist") -> Track {
        Track(discID: "album", number: "1", title: "Song", artists: artists, albumTitle: "Album", coverURL: nil,
              remoteSource: .init(providerID: provider, itemID: "song"))
    }
}

private enum ArtistFixtureError: Error { case unavailable }
@MainActor private final class ArtistFixtureModule: AppModule {
    let descriptor: ModuleDescriptor
    var requests = 0
    var resolve: () async throws -> [PlayerArtistDestination] = { [] }
    var artistNavigation = PlayerArtistNavigation.perArtist
    init(_ id: String) { descriptor = .init(id: ModuleID(rawValue: id), title: id, systemImage: "music.note") }
    func rootView() -> AnyView { AnyView(EmptyView()) }
    func destination(for route: AppRoute) -> AnyView? { nil }
    func artistDestinations(for track: Track) async throws -> [PlayerArtistDestination] {
        requests += 1
        return try await resolve()
    }
}
