import SwiftUI
import Testing
@testable import NeoDizzy

@MainActor
struct SongLibraryActionsTests {
    private final class Provider: AppModule {
        let descriptor: ModuleDescriptor
        var songActionVisits = 0
        init(_ id: String = "test-provider") {
            descriptor = ModuleDescriptor(id: ModuleID(rawValue: id), title: "Test", systemImage: "music.note")
        }
        func songActions(for track: Track, onImportLyrics: (() -> Void)?) -> AnyView? {
            songActionVisits += 1
            return AnyView(Text("Actions"))
        }
        func rootView() -> AnyView { AnyView(EmptyView()) }
        func destination(for route: AppRoute) -> AnyView? { nil }
        func playlistPicker(for track: Track) -> AnyView? { track.remoteSource?.itemID == "42" ? AnyView(Text("Picker")) : nil }
    }
    private func track(provider: String = "test-provider", id: String = "42", local: Bool = false) -> Track {
        Track(discID: "album", number: "1", title: "Song", artists: "Artist", albumTitle: "Album", coverURL: nil,
              localSource: local ? LocalTrackSource(albumID: "album", trackID: "local-song") : nil,
              remoteSource: RemoteTrackSource(providerID: provider, itemID: id))
    }
    @Test func downloadedSongsKeepTheirRegisteredPlatformPicker() throws {
        let registry = try ModuleRegistry([Provider()])
        #expect(registry.playlistPicker(for: track(local: true)) != nil)
        #expect(registry.playlistPicker(for: track()) != nil)
        #expect(registry.playlistPicker(for: track(id: "invalid")) == nil)
    }
    @Test func removingProviderRemovesItsCapabilitiesWithoutFallbackToAnother() throws {
        let registry = try ModuleRegistry([Provider()])
        #expect(registry.playlistPicker(for: track(provider: "unknown")) == nil)
        registry.remove(ModuleID(rawValue: "test-provider"))
        #expect(registry.playlistPicker(for: track()) == nil)
        #expect(registry.descriptors.isEmpty)
        #expect(registry.origin(providerID: "test-provider") == nil)
        #expect(registry.origin(providerID: "local") == .local)
        try registry.register(Provider())
        #expect(registry.playlistPicker(for: track()) != nil)
        #expect(throws: ModuleRegistry.RegistrationError.self) { try registry.register(Provider()) }
        #expect(registry.descriptors.count == 1)
    }
    @Test func songActionsAreDispatchedOnlyToTheirOwner() throws {
        let first = Provider("first"), second = Provider("second")
        let registry = try ModuleRegistry([first, second])
        #expect(registry.songActions(for: track(provider: "second"), onImportLyrics: nil) != nil)
        #expect(first.songActionVisits == 0)
        #expect(second.songActionVisits == 1)
        registry.remove(ModuleID(rawValue: "second"))
        #expect(registry.songActions(for: track(provider: "second"), onImportLyrics: nil) == nil)
        #expect(first.songActionVisits == 0)
    }

}
