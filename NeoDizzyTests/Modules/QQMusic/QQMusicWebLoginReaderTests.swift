import Foundation
import Testing
@testable import NeoDizzy

@MainActor struct QQMusicWebLoginReaderTests {
    private let first = QQMusicCredential(musicID: "123", musicKey: "first-key")
    private let next = QQMusicCredential(musicID: "456", musicKey: "next-key")

    @Test func separatelyWrittenCookiesBecomeOneStableCredential() async throws {
        let complete = try cookies(for: first)
        let snapshots = [[], [complete[0]], complete, complete]
        var reads = 0
        var pauses = 0

        let credential = try await QQMusicWebLoginReader.credential(readCookies: {
            let snapshot = snapshots[min(reads, snapshots.count - 1)]
            reads += 1
            return snapshot
        }, pause: { pauses += 1 })

        #expect(credential == first)
        #expect(reads == 4)
        #expect(pauses == 3)
    }

    @Test func completeCookiesStillRequireASecondMatchingRead() async throws {
        let complete = try cookies(for: first)
        var reads = 0
        var pauses = 0

        let credential = try await QQMusicWebLoginReader.credential(readCookies: {
            reads += 1
            return complete
        }, pause: { pauses += 1 })

        #expect(credential == first)
        #expect(reads == 2)
        #expect(pauses == 1)
    }

    @Test func changingCredentialMustStabilizeBeforeReturning() async throws {
        let snapshots = try [cookies(for: first), cookies(for: next), cookies(for: next)]
        var reads = 0
        var pauses = 0

        let credential = try await QQMusicWebLoginReader.credential(readCookies: {
            let snapshot = snapshots[min(reads, snapshots.count - 1)]
            reads += 1
            return snapshot
        }, pause: { pauses += 1 })

        #expect(credential == next)
        #expect(reads == 3)
        #expect(pauses == 2)
    }

    @Test func everyTransientExtractionErrorResetsPreviousStability() async throws {
        let complete = try cookies(for: first)
        for (invalid, _) in try invalidSnapshots() {
            let snapshots = [complete, invalid, complete, complete]
            var reads = 0

            let credential = try await QQMusicWebLoginReader.credential(readCookies: {
                let snapshot = snapshots[min(reads, snapshots.count - 1)]
                reads += 1
                return snapshot
            }, pause: {})

            #expect(credential == first)
            #expect(reads == 4)
        }
    }

    @Test func timeoutsRetainTheFinalSpecificExtractionError() async throws {
        for (invalid, expected) in try invalidSnapshots() {
            var reads = 0
            var pauses = 0

            await #expect(throws: expected) {
                try await QQMusicWebLoginReader.credential(readCookies: {
                    reads += 1
                    return invalid
                }, pause: { pauses += 1 })
            }

            #expect(reads == 8)
            #expect(pauses == 7)
        }
    }

    @Test func continuouslyChangingCompleteCookiesNeverReturnAnUnstableAccount() async throws {
        let firstCookies = try cookies(for: first)
        let nextCookies = try cookies(for: next)
        var reads = 0
        var pauses = 0

        await #expect(throws: QQMusicLoginError.ambiguousCookies) {
            try await QQMusicWebLoginReader.credential(readCookies: {
                reads += 1
                return reads.isMultiple(of: 2) ? nextCookies : firstCookies
            }, pause: { pauses += 1 })
        }

        #expect(reads == 8)
        #expect(pauses == 7)
    }

    @Test func firstCompleteCredentialOnFinalReadHasNotYetStabilized() async throws {
        let complete = try cookies(for: first)
        var reads = 0

        await #expect(throws: QQMusicLoginError.ambiguousCookies) {
            try await QQMusicWebLoginReader.credential(readCookies: {
                reads += 1
                return reads == 8 ? complete : []
            }, pause: {})
        }

        #expect(reads == 8)
    }

    @Test func cancellationDuringFinalCookieReadCannotReturnStableCredential() async throws {
        let complete = try cookies(for: first)
        let gate = WebLoginReaderGate()
        var reads = 0
        let work = Task {
            try await QQMusicWebLoginReader.credential(readCookies: {
                reads += 1
                if reads == 2 { await gate.wait() }
                // The website cookie store can finish an in-flight read after cancellation.
                return complete
            }, pause: {})
        }
        await gate.waitForStart()

        work.cancel()
        await gate.release()
        await #expect(throws: CancellationError.self) { try await work.value }
        #expect(reads == 2)
    }

    private func invalidSnapshots() throws -> [([HTTPCookie], QQMusicLoginError)] {
        let complete = try cookies(for: first)
        let conflicting = try complete + [cookie("qqmusic_key", "conflicting-key")]
        return [
            ([], .loginRequired),
            ([complete[0]], .musicAuthorizationPending),
            ([complete[1]], .accountIdentifierMissing),
            (conflicting, .ambiguousCookies)
        ]
    }

    private func cookies(for credential: QQMusicCredential) throws -> [HTTPCookie] {
        try [cookie("qqmusic_uin", credential.musicID), cookie("qqmusic_key", credential.musicKey)]
    }

    private func cookie(_ name: String, _ value: String) throws -> HTTPCookie {
        try #require(HTTPCookie(properties: [.name: name, .value: value, .domain: ".y.qq.com", .path: "/", .secure: "TRUE"]))
    }
}

private actor WebLoginReaderGate {
    private var response: CheckedContinuation<Void, Never>?
    private var started: CheckedContinuation<Void, Never>?

    func wait() async {
        await withCheckedContinuation { continuation in
            response = continuation
            started?.resume()
            started = nil
        }
    }

    func waitForStart() async {
        if response != nil { return }
        await withCheckedContinuation { started = $0 }
    }

    func release() {
        response?.resume()
        response = nil
    }
}
