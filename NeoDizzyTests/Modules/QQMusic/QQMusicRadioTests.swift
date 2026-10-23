import Foundation
import Testing
@testable import NeoDizzy

@MainActor struct QQMusicRadioTests {
    private func track(_ number: Int) -> Track {
        Track(discID: "radio", number: String(number), title: "Song \(number)", artists: "", albumTitle: "", coverURL: nil,
              remoteSource: .init(providerID: "qqmusic", itemID: String(number)))
    }

    @Test func continuesInServerOrderWithoutDuplicatesWithinOrBetweenBatches() async throws {
        var requests = 0
        let session = QQMusicRadioSession {
            requests += 1
            switch requests {
            case 1: return [track(1), track(1), track(2), track(3)]
            case 2: return [track(3), track(4), track(4), track(2), track(5)]
            default: return [track(6), track(7), track(8)]
            }
        }
        defer { session.reset() }

        var played = [try await session.start().number]
        for _ in 0..<4 { played.append(try await session.next().number) }

        #expect(played == ["1", "2", "3", "4", "5"])
        #expect(requests <= 3)
    }

    @Test func initialSongsPrefetchOnlyOneBatchWhenNearlyConsumed() async throws {
        let gate = RadioBatchGate()
        var requests = 0
        let session = QQMusicRadioSession {
            requests += 1
            return await gate.wait()
        }
        #expect(try await session.start(with: [track(1), track(1), track(2), track(3), track(4)]).number == "1")
        #expect(try await session.next().number == "2")
        #expect(requests == 0)
        #expect(try await session.next().number == "3")
        await gate.waitForStart()
        #expect(try await session.next().number == "4")
        #expect(requests == 1)

        session.reset()
        await gate.release([])
    }

    @Test func concurrentConsumersShareFetchAndConsumeDistinctSongsOnce() async throws {
        let gate = RadioBatchGate()
        var requests = 0
        let session = QQMusicRadioSession {
            requests += 1
            return await gate.wait()
        }
        defer { session.reset() }
        let first = Task { try await session.start() }
        await gate.waitForStart()
        var secondStarted = false
        let second = Task {
            secondStarted = true
            return try await session.next()
        }
        while !secondStarted { await Task.yield() }

        await gate.release([track(1), track(2), track(3), track(4)])
        #expect(try await first.value.number == "1")
        #expect(try await second.value.number == "2")
        #expect(requests == 1)
    }

    @Test func failedBatchCanBeRetriedWithoutPoisoningTheSession() async throws {
        var requests = 0
        let session = QQMusicRadioSession {
            requests += 1
            if requests == 1 { throw URLError(.notConnectedToInternet) }
            return [track(4), track(5), track(6)]
        }
        defer { session.reset() }

        await #expect(throws: URLError.self) { try await session.start() }
        #expect(requests == 1)
        #expect(try await session.next().number == "4")
        #expect(requests == 2)
    }

    @Test func repeatedlyIdenticalBatchesStopAfterBoundedRetriesAndCanRecover() async throws {
        var requests = 0
        let session = QQMusicRadioSession {
            requests += 1
            return requests <= 3 ? [track(1), track(1)] : [track(2), track(3), track(4)]
        }
        defer { session.reset() }
        #expect(try await session.start(with: [track(1)]).number == "1")

        await #expect(throws: QQMusicError.self) { try await session.next() }
        #expect(requests == 3)
        #expect(try await session.next().number == "2")
        #expect(requests == 4)
    }

    @Test func emptyBatchesHaveTheSameBoundedRetryLimit() async {
        var requests = 0
        let session = QQMusicRadioSession {
            requests += 1
            return []
        }
        defer { session.reset() }

        await #expect(throws: QQMusicError.self) { try await session.start() }
        #expect(requests == 3)
    }

    @Test func resetRejectsLateBatchAndReleasesOldWaitersWithoutBlockingNewSession() async throws {
        let gate = RadioBatchGate()
        var requests = 0
        let session = QQMusicRadioSession {
            requests += 1
            if requests == 1 { return await gate.wait() }
            return [track(8), track(9), track(10)]
        }
        defer { session.reset() }
        let old = Task { try await session.start() }
        await gate.waitForStart()
        var waiterStarted = false
        let waiter = Task {
            waiterStarted = true
            return try await session.next()
        }
        while !waiterStarted { await Task.yield() }

        session.reset()
        await #expect(throws: CancellationError.self) { try await waiter.value }
        #expect(try await session.start().number == "8")
        // The old fetch ignores cancellation and responds after the new session.
        await gate.release([track(1), track(2), track(3)])
        await #expect(throws: CancellationError.self) { try await old.value }
        #expect(try await session.next().number == "9")
    }

    @Test func cancellingActiveConsumerDoesNotCancelSharedFetchOrConsumeASong() async throws {
        let gate = RadioBatchGate()
        var requests = 0
        let session = QQMusicRadioSession {
            requests += 1
            return await gate.wait()
        }
        defer { session.reset() }
        let first = Task { try await session.start() }
        await gate.waitForStart()
        var secondStarted = false
        let second = Task {
            secondStarted = true
            return try await session.next()
        }
        while !secondStarted { await Task.yield() }
        first.cancel()

        await gate.release([track(1), track(2), track(3), track(4)])
        await #expect(throws: CancellationError.self) { try await first.value }
        #expect(try await second.value.number == "1")
        #expect(requests == 1)
    }

    @Test func cancellingQueuedConsumerDoesNotBlockTheFollowingConsumer() async throws {
        let gate = RadioBatchGate()
        var requests = 0
        let session = QQMusicRadioSession {
            requests += 1
            return await gate.wait()
        }
        defer { session.reset() }
        let first = Task { try await session.start() }
        await gate.waitForStart()
        var cancelledStarted = false
        let cancelled = Task {
            cancelledStarted = true
            return try await session.next()
        }
        while !cancelledStarted { await Task.yield() }
        cancelled.cancel()
        await #expect(throws: CancellationError.self) { try await cancelled.value }
        let third = Task { try await session.next() }

        await gate.release([track(1), track(2), track(3), track(4)])
        #expect(try await first.value.number == "1")
        #expect(try await third.value.number == "2")
        #expect(requests == 1)
    }

    @Test func logoutDropsBufferedSongsBeforeFurtherRadioRequests() async throws {
        let store = QQMusicStore(restoreSaved: false, saveCredential: { _ in })
        #expect(try await store.radio.start(with: [track(1), track(2), track(3)]).number == "1")

        await store.signOut()

        // Guest radio is rejected locally by the client, without a network request.
        // A stale buffer would incorrectly return song 2 here.
        await #expect(throws: QQMusicError.self) { try await store.radio.next() }
    }

    @Test func deactivationDropsBufferedRadioSongs() async throws {
        let store = QQMusicStore(restoreSaved: false, saveCredential: { _ in })
        #expect(try await store.radio.start(with: [track(1), track(2), track(3)]).number == "1")
        await store.api.setEnabled(false)

        store.deactivate()

        await #expect(throws: QQMusicError.self) { try await store.radio.next() }
    }
}

/// Models an in-flight server callback that does not cooperate with cancellation.
private actor RadioBatchGate {
    private var response: CheckedContinuation<[Track], Never>?
    private var started: CheckedContinuation<Void, Never>?

    func wait() async -> [Track] {
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

    func release(_ songs: [Track]) {
        response?.resume(returning: songs)
        response = nil
    }
}
