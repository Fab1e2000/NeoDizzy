import Testing
@testable import NeoDizzy

@MainActor
struct AudioSessionActivationTests {
    @Test func pendingRequestsCoalesceAndLatestCompletionWins() {
        let coordinator = AudioSessionActivationCoordinator()
        var finish: AudioSessionActivationCoordinator.Completion?
        var starts = 0
        var delivered: [Int] = []
        let start: AudioSessionActivationCoordinator.Start = { completion in
            starts += 1
            finish = completion
        }
        coordinator.request(start: start) { _ in delivered.append(1) }
        coordinator.request(start: start) { _ in delivered.append(2) }
        #expect(starts == 1)
        finish?(.success(()))
        #expect(delivered == [2])
    }

    @Test func resumeDuringOutstandingActivationUsesOneOperation() {
        let coordinator = AudioSessionActivationCoordinator()
        var finish: AudioSessionActivationCoordinator.Completion?
        var starts = 0
        var delivered: [String] = []
        let start: AudioSessionActivationCoordinator.Start = { completion in
            starts += 1
            finish = completion
        }
        coordinator.request(start: start) { _ in delivered.append("before interruption") }
        coordinator.cancel()
        coordinator.request(start: start) { _ in delivered.append("resume") }
        #expect(starts == 1)
        finish?(.success(()))
        #expect(delivered == ["resume"])
    }

    @Test func cancelledIntentCannotResumeAndFailureDoesNotRetry() {
        enum Failure: Error { case denied }
        let coordinator = AudioSessionActivationCoordinator()
        var finish: AudioSessionActivationCoordinator.Completion?
        var starts = 0
        var delivered = 0
        let start: AudioSessionActivationCoordinator.Start = { completion in
            starts += 1
            finish = completion
        }
        coordinator.request(start: start) { _ in delivered += 1 }
        coordinator.cancel()
        finish?(.success(()))
        #expect(delivered == 0)
        coordinator.request(start: start) { result in
            if case .failure = result { delivered += 1 }
        }
        finish?(.failure(Failure.denied))
        #expect(delivered == 1)
        #expect(starts == 2)
    }
}

#if os(iOS)
import AVFoundation

@Suite(.serialized) @MainActor
struct PlayerSessionActivationTests {
    private final class Gate {
        var finish: AudioSessionActivationCoordinator.Completion?
        var calls = 0
        func start(_ completion: @escaping AudioSessionActivationCoordinator.Completion) {
            calls += 1
            finish = completion
        }
        func complete(_ result: Result<Void, Error> = .success(())) {
            let callback = finish
            finish = nil
            callback?(result)
        }
    }
    private struct Rig {
        let store: PlayerStore
        let engine: AVQueuePlayer
        let gate: Gate
        let file: URL
        let defaults: UserDefaults
        let suite: String
        func track(_ number: Int) -> Track {
            Track(discID: "session", number: String(number), title: "Track", artists: "", albumTitle: "", coverURL: nil)
        }
        func clean() {
            store.pause()
            gate.complete()
            defaults.removePersistentDomain(forName: suite)
            try? FileManager.default.removeItem(at: file)
        }
    }
    private func rig(remote: Bool = false) throws -> Rig {
        let suite = "PlayerSessionActivationTests.\(UUID())"
        let defaults = try #require(UserDefaults(suiteName: suite))
        let file = FileManager.default.temporaryDirectory.appendingPathComponent("\(UUID()).wav")
        let format = try #require(AVAudioFormat(standardFormatWithSampleRate: 8000, channels: 1))
        let buffer = try #require(AVAudioPCMBuffer(pcmFormat: format, frameCapacity: 80000))
        buffer.frameLength = buffer.frameCapacity
        buffer.floatChannelData?[0].initialize(repeating: 0, count: Int(buffer.frameLength))
        do { let output = try AVAudioFile(forWriting: file, settings: format.settings); try output.write(from: buffer) }
        let gate = Gate()
        let engine = AVQueuePlayer()
        let resolver = StreamResolver(localFile: { _ in remote ? nil : file })
        if remote {
            resolver.register("dizzylab", provider: PlaybackProvider(stream: { _ in
                RemotePlaybackSource(url: URL(string: "https://127.0.0.1:1/session-fixture.wav")!,
                                     expiresAt: .distantFuture, isPreview: false)
            }))
        }
        let store = PlayerStore(resolver: resolver, persistence: PlaybackPersistence(defaults: defaults),
                                activation: gate.start, playbackPlayer: engine)
        return Rig(store: store, engine: engine, gate: gate, file: file, defaults: defaults, suite: suite)
    }
    private func wait(_ condition: () -> Bool) async throws {
        for _ in 0..<200 {
            if condition() { return }
            try await Task.sleep(for: .milliseconds(10))
        }
        Issue.record("Timed out waiting for activation")
    }
    @Test func pauseAndEditingStopDiscardPendingActivation() async throws {
        for editing in [false, true] {
            let r = try rig(); defer { r.clean() }
            r.store.play([r.track(1)], startAt: 0)
            try await wait { r.gate.calls == 1 }
            if editing { r.store.stopForTagEditing(r.file) } else { r.store.pause() }
            r.gate.complete()
            #expect(!r.store.isPlaying)
            #expect(r.engine.rate == 0)
            if editing { #expect(!r.store.holdsFile(r.file)) }
        }
    }
    @Test func playbackPreservingCommandsDoNotDiscardPendingActivation() async throws {
        for command in ["seek", "next", "previous", "restart", "shuffle", "repeat"] {
            let r = try rig(); defer { r.clean() }
            r.store.play([r.track(1)], startAt: 0)
            try await wait { r.gate.calls == 1 }
            switch command {
            case "seek": r.store.seek(to: 1)
            case "next": r.store.next()
            case "previous": r.store.previous()
            case "restart": r.store.seek(to: 4); r.store.previous()
            case "shuffle": r.store.toggleShuffle()
            default: r.store.cycleRepeatMode()
            }
            r.gate.complete()
            #expect(r.store.isPlaying, "Command: \(command)")
            #expect(r.engine.rate == 1, "Command: \(command)")
            #expect(r.gate.calls == 1)
        }
    }

    @Test func replacementItemWinsWhileActivationIsPending() async throws {
        let r = try rig(); defer { r.clean() }
        r.store.play([r.track(1)], startAt: 0)
        try await wait { r.gate.calls == 1 }
        let previous = r.engine.currentItem
        r.store.play([r.track(2)], startAt: 0)
        try await wait { r.engine.currentItem != nil && r.engine.currentItem !== previous }
        r.gate.complete()
        #expect(r.gate.calls == 1)
        #expect(r.store.currentTrack?.number == "2")
        #expect(r.engine.rate == 1)
    }
    @Test func disablingOnlineProviderDiscardsPendingActivation() async throws {
        let r = try rig(remote: true); defer { r.clean() }
        r.store.play([r.track(1)], startAt: 0)
        try await wait { r.gate.calls == 1 }
        await r.store.disableProvider(providerID: "dizzylab")
        r.gate.complete()
        #expect(!r.store.isPlaying)
        #expect(r.engine.rate == 0)
        #expect(r.engine.currentItem == nil)
    }

    @Test func activationFailureIsVisibleAndDoesNotRetry() async throws {
        let r = try rig(); defer { r.clean() }
        r.store.play([r.track(1)], startAt: 0)
        try await wait { r.gate.calls == 1 }
        r.gate.complete(.failure(PlaybackError.unavailable))
        #expect(r.store.issue?.contains("激活音频会话失败") == true)
        #expect(!r.store.isPlaying)
        #expect(r.engine.rate == 0)
        #expect(r.gate.calls == 1)
    }
    @Test func interruptionResumeAndExplicitPauseRespectLatestIntent() async throws {
        for paused in [false, true] {
            let r = try rig(); defer { r.clean() }
            r.store.play([r.track(1)], startAt: 0)
            try await wait { r.gate.calls == 1 }
            r.store.sessionWasInterrupted(routeDisconnected: false)
            if paused { r.store.pause() }
            r.store.sessionResumptionRecommended(shouldResume: true)
            r.gate.complete()
            #expect(r.store.isPlaying == !paused)
            #expect(r.engine.rate == (paused ? 0 : 1))
            #expect(r.gate.calls == 1)
        }
    }
}
#endif
