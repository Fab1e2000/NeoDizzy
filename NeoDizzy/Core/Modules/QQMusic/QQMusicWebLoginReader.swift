import Foundation

/// Web authorization can write its identity and music ticket in separate steps.
/// Wait briefly for a stable pair without starting network validation for every cookie change.
@MainActor enum QQMusicWebLoginReader {
    static func credential(
        readCookies: () async throws -> [HTTPCookie],
        pause: () async throws -> Void = { try await Task.sleep(for: .milliseconds(400)) }
    ) async throws -> QQMusicCredential {
        var previous: QQMusicCredential?
        for attempt in 0..<8 {
            try Task.checkCancellation()
            let cookies = try await readCookies()
            try Task.checkCancellation()
            do {
                let candidate = try QQMusicLoginClient.credential(from: cookies)
                if candidate == previous { return candidate }
                previous = candidate
                // A pair first observed on the final read has not settled yet.
                if attempt == 7 { throw QQMusicLoginError.ambiguousCookies }
            } catch let error as QQMusicLoginError {
                switch error {
                case .loginRequired, .musicAuthorizationPending, .accountIdentifierMissing, .ambiguousCookies:
                    previous = nil
                    if attempt == 7 { throw error }
                default:
                    throw error
                }
            }
            try await pause()
        }
        throw QQMusicLoginError.ambiguousCookies
    }
}
