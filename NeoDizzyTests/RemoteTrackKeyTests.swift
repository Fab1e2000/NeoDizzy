import XCTest
@testable import NeoDizzy

final class RemoteTrackKeyTests: XCTestCase {
    func testLegacyDizzyLabIdentityAndSnapshot() throws {
        let data = Data(#"{"discID":"album","number":"02","title":"歌曲","artists":"歌手","albumTitle":"专辑"}"#.utf8)
        let track = try JSONDecoder().decode(Track.self, from: data)
        XCTAssertEqual(track.remoteKey, RemoteTrackKey(provider: "dizzylab", itemID: "album/02"))
        XCTAssertEqual(track.id, "album/02")
        let encoded = try JSONEncoder().encode(track)
        let fields = try XCTUnwrap(JSONSerialization.jsonObject(with: encoded) as? [String: Any])
        XCTAssertEqual(Set(fields.keys), ["discID", "number", "title", "artists", "albumTitle"])
        XCTAssertEqual(try JSONDecoder().decode(Track.self, from: encoded), track)
    }

    func testRemoteSourceTakesPrecedenceAndPreservesIdentity() throws {
        var track = makeTrack()
        track.remoteSource = RemoteTrackSource(providerID: "netease", itemID: "123")
        XCTAssertEqual(track.remoteKey, RemoteTrackKey(provider: "netease", itemID: "123"))
        XCTAssertEqual(track.id, "remote/netease/123")
        track.localSource = LocalTrackSource(albumID: "local-album", trackID: "local-song")
        XCTAssertEqual(track.remoteKey, RemoteTrackKey(provider: "netease", itemID: "123"))
        XCTAssertEqual(track.id, "remote/netease/123")
        let restored = try JSONDecoder().decode(Track.self, from: JSONEncoder().encode(track))
        XCTAssertEqual(restored, track)
        XCTAssertEqual(restored.remoteKey, track.remoteKey)
    }

    func testLocalAndUnidentifiedTracksHaveNoRemoteKey() {
        var track = makeTrack()
        track.localSource = LocalTrackSource(albumID: "local-album", trackID: "local-song")
        XCTAssertNil(track.remoteKey)
        XCTAssertEqual(track.id, "local/local-song")
        XCTAssertNil(makeTrack(discID: "").remoteKey)
    }

    func testKeysKeepProviderNamespacesAndRoundTrip() throws {
        let keys: Set<RemoteTrackKey> = [
            RemoteTrackKey(provider: "dizzylab", itemID: "123"),
            RemoteTrackKey(provider: "netease", itemID: "123"),
            RemoteTrackKey(provider: "netease", itemID: "123")
        ]
        XCTAssertEqual(keys.count, 2)
        XCTAssertEqual(try JSONDecoder().decode(Set<RemoteTrackKey>.self, from: JSONEncoder().encode(keys)), keys)
    }

    private func makeTrack(discID: String = "album") -> Track {
        Track(discID: discID, number: "1", title: "歌曲", artists: "歌手", albumTitle: "专辑", coverURL: nil)
    }
}
