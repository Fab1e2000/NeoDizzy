import Foundation

/// One system operation at a time. A newer request replaces the consumer, never
/// starts a second activation or retries a failed activation implicitly.
@MainActor
final class AudioSessionActivationCoordinator {
    typealias Completion = @MainActor @Sendable (Result<Void, Error>) -> Void
    typealias Start = @MainActor @Sendable (@escaping Completion) -> Void
    private var inFlight = false
    private var completion: Completion?

    func request(start: Start, completion: @escaping Completion) {
        self.completion = completion
        guard !inFlight else { return }
        inFlight = true
        start { [weak self] result in
            guard let self else { return }
            self.inFlight = false
            let consumer = self.completion
            self.completion = nil
            consumer?(result)
        }
    }

    func cancel() { completion = nil }
}
