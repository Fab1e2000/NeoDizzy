import Foundation
import Testing
@testable import NeoDizzy

@MainActor struct DownloadRateTests {
    @Test func measuresByteDeltasAndExpiresStalledSpeed() {
        let progress = DownloadProgress(fraction: nil)
        let start = ContinuousClock.now
        progress.update(received: 1_000, expected: 10_000, now: start)
        #expect(progress.bytesPerSecond == 0)
        progress.update(received: 3_000, expected: 10_000, now: start.advanced(by: .milliseconds(500)))
        #expect(progress.bytesPerSecond == 4_000)
        #expect(progress.fraction == 0.3)
        #expect(progress.speed(at: progress.updatedAt.addingTimeInterval(3)) == 0)
        progress.finish()
        #expect(progress.bytesPerSecond == 0)
    }

    @Test func unknownLengthStillReportsSpeedAndRestartDoesNotGoNegative() {
        let progress = DownloadProgress(fraction: nil)
        let start = ContinuousClock.now
        progress.update(received: 1_000, expected: -1, now: start)
        progress.update(received: 2_000, expected: -1, now: start.advanced(by: .seconds(1)))
        #expect(progress.fraction == nil)
        #expect(progress.bytesPerSecond == 1_000)
        progress.update(received: 100, expected: 10_000, now: start.advanced(by: .seconds(2)))
        #expect(progress.bytesPerSecond == 0)
        #expect(progress.fraction == 0.01)
    }
}
