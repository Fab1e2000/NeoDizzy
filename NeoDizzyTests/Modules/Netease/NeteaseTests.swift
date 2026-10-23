import CommonCrypto
import CryptoKit
import Foundation
import Testing
@testable import NeoDizzy

@MainActor
struct NeteaseTests {
    private func remote(_ id: String = "42") -> Track {
        Track(discID: "7", number: id, title: "Song", artists: "Artist", albumTitle: "Album", coverURL: nil,
              remoteSource: .init(providerID: "netease", itemID: id))
    }
    @Test func decodesBothSongShapesAndKeepsSourceIdentity() throws {
        for json in [
            #"{"id":42,"name":"Song","ar":[{"id":1,"name":"Artist"}],"al":{"id":7,"name":"Album","picUrl":"http://p1.music.126.net/cover.jpg"},"dt":180000}"#,
            #"{"id":42,"name":"Song","artists":[{"id":1,"name":"Artist"}],"album":{"id":7,"name":"Album","picUrl":"http://p1.music.126.net/cover.jpg"},"duration":180000}"#
        ] {
            let song = try JSONDecoder().decode(NeteaseSong.self, from: Data(json.utf8))
            #expect(song.track.id == "remote/netease/42")
            #expect(song.track.duration == 180)
            #expect(song.track.coverURL?.scheme == "https")
            #expect(song.track.artists == "Artist")
        }
        let old = try JSONDecoder().decode(Track.self, from: Data(#"{"discID":"7","number":"42","title":"Old","artists":"","albumTitle":""}"#.utf8))
        #expect(old.remoteSource == nil)
        #expect(old.id == "7/42")
        #expect(old.id != remote().id)
        #expect(try JSONDecoder().decode(Track.self, from: JSONEncoder().encode(remote())) == remote())
    }
    @Test func eapiUsesCanonicalFrameAndOnlyNeteaseCredentials() throws {
        let defaults = try #require(UserDefaults(suiteName: "NeteaseTests.\(UUID())"))
        let client = NeteaseClient(defaults: defaults)
        client.cookie = "MUSIC_U=fake-token; __csrf=fake-csrf; dizzy_token=must-not-send"
        let request = try client.makeRequest("/api/search/get", data: ["s": "音乐", "type": 1], authenticated: true)
        #expect(request.url?.absoluteString == "https://interface.music.163.com/eapi/search/get")
        #expect(!request.httpShouldHandleCookies)
        #expect(request.value(forHTTPHeaderField: "Cookie")?.contains("must-not-send") == false)
        let hex = String(decoding: try #require(request.httpBody), as: UTF8.self).dropFirst(7)
        var encrypted = Data()
        var index = hex.startIndex
        while index < hex.endIndex {
            let end = hex.index(index, offsetBy: 2)
            encrypted.append(try #require(UInt8(hex[index..<end], radix: 16))); index = end
        }
        var output = Data(count: encrypted.count + 16)
        let capacity = output.count
        var length = 0
        let status = output.withUnsafeMutableBytes { dest in
            encrypted.withUnsafeBytes { src in
                "e82ckenh8dichen8".withCString { key in
                    CCCrypt(CCOperation(kCCDecrypt), CCAlgorithm(kCCAlgorithmAES), CCOptions(kCCOptionECBMode | kCCOptionPKCS7Padding), key, 16, nil, src.baseAddress, encrypted.count, dest.baseAddress, capacity, &length)
                }
            }
        }
        #expect(status == kCCSuccess)
        let parts = String(decoding: output.prefix(length), as: UTF8.self).components(separatedBy: "-36cd479b6b5-")
        #expect(parts.count == 3)
        #expect(parts[0] == "/api/search/get")
        let object = try #require(JSONSerialization.jsonObject(with: Data(parts[1].utf8)) as? [String: Any])
        #expect(object["s"] as? String == "音乐")
        #expect((object["header"] as? [String: String])?["MUSIC_U"] == "fake-token")
        let digest = Insecure.MD5.hash(data: Data("nobody\(parts[0])use\(parts[1])md5forencrypt".utf8)).map { String(format: "%02x", $0) }.joined()
        #expect(parts[2] == digest)
        client.cookie = ""
        #expect(throws: NeteaseError.self) { try client.makeRequest("/api/user/playlist", data: [:], authenticated: true) }
    }
    @Test func routesRemoteStreamsAfterLocalLookupAndExpiresCache() async throws {
        var calls = 0
        var now = Date(timeIntervalSince1970: 1000)
        let resolver = StreamResolver(now: { now }, localFile: { _ in nil })
        let url = URL(string: "https://example.com/song.mp3")!
        resolver.register("netease", stream: { _ in calls += 1; return .init(url: url, expiresAt: now.addingTimeInterval(600), isPreview: true) }, lyrics: { _ in .parse("[00:01]line") })
        #expect(try await resolver.stream(for: remote()) == url)
        _ = try await resolver.stream(for: remote())
        #expect(calls == 1)
        #expect(resolver.isPreview(for: remote(), url: url))
        now = now.addingTimeInterval(601)
        _ = try await resolver.stream(for: remote())
        #expect(calls == 2)
        resolver.invalidate(for: remote())
        _ = try await resolver.stream(for: remote())
        #expect(calls == 3)
        #expect(try await resolver.lyrics(for: remote())?.isTimed == true)
    }
    @Test func unknownProviderNeverFallsBackToDizzyLab() async {
        let resolver = StreamResolver()
        do { _ = try await resolver.stream(for: remote()); Issue.record("Expected unavailable") }
        catch { #expect(error as? PlaybackError == .unavailable) }
    }
    @Test func sessionChangeRejectsInFlightStream() async {
        let resolver = StreamResolver()
        resolver.register("netease", stream: { _ in
            resolver.removeAll()
            return .init(url: URL(string: "https://example.com/old.mp3")!, expiresAt: .distantFuture, isPreview: false)
        }, lyrics: { _ in .parse("") })
        do { _ = try await resolver.stream(for: remote()); Issue.record("Old session survived") }
        catch { #expect(error is CancellationError) }
    }
}
