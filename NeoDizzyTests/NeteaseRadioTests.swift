import Foundation
import Testing
@testable import NeoDizzy

@MainActor
struct NeteaseRadioTests {
    private func track(_ number: Int) -> Track {
        Track(discID: "fm", number: String(number), title: "Song", artists: "", albumTitle: "", coverURL: nil)
    }
    @Test func continuesPastThreeSongsInServerOrder() async throws {
        var requests = 0
        let session = NeteaseRadioSession {
            requests += 1
            return [track(4), track(5), track(6)]
        }
        #expect(try await session.start(with: [track(1), track(2), track(3)]).number == "1")
        #expect(requests == 0)
        #expect(try await session.next().number == "2")
        #expect(try await session.next().number == "3")
        #expect(try await session.next().number == "4")
        #expect(requests == 1)
    }
    @Test func failedBatchCanBeRetried() async throws {
        var requests = 0
        let session = NeteaseRadioSession {
            requests += 1
            if requests == 1 { throw NeteaseError.unavailable }
            return [track(4)]
        }
        do { _ = try await session.start(with: []); Issue.record("Expected failure") }
        catch { #expect(requests == 1) }
        #expect(try await session.next().number == "4")
    }
    @Test func resetDiscardsPreviousBatch() async throws {
        let session = NeteaseRadioSession { [track(8), track(9)] }
        _ = try await session.start(with: [track(1), track(2), track(3)])
        session.reset()
        #expect(try await session.next().number == "8")
    }
}
