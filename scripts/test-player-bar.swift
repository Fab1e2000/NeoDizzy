import CoreGraphics

/// Run with the production value type, without launching the app:
/// xcrun swiftc -swift-version 5 -default-isolation MainActor \
///   -enable-upcoming-feature InferIsolatedConformances \
///   NeoDizzyMac/Features/Player/PlayerBarControlVisibility.swift \
///   scripts/test-player-bar.swift -o /tmp/neodizzy-player-bar-checks
/// /tmp/neodizzy-player-bar-checks
@main
struct PlayerBarControlVisibilityChecks {
    static func main() {
        // Preserve the existing control visibility at and around both boundaries.
        for width in stride(from: CGFloat(0), through: 1600, by: 0.25) {
            let controls = PlayerBarControlVisibility(width: width)
            precondition(controls.showsModes == (width >= 900))
            precondition(controls.showsVolumeSlider == (width >= 720))
        }
        precondition(PlayerBarControlVisibility(width: 720).showsVolumeSlider)
        precondition(!PlayerBarControlVisibility(width: 720.nextDown).showsVolumeSlider)
        precondition(PlayerBarControlVisibility(width: 900).showsModes)
        precondition(!PlayerBarControlVisibility(width: 900.nextDown).showsModes)

        // Layout keeps receiving every actual width, but geometry-driven state
        // only changes when controls need to appear/disappear, in either direction.
        let widths = Array(stride(from: CGFloat(1000), through: 600, by: -0.25))
        precondition(changes(in: widths) == 2)
        precondition(changes(in: Array(widths.reversed())) == 2)
        precondition(changes(in: Array(stride(from: CGFloat(1180), through: 902, by: -0.25))) == 0)
        print("Player bar checks passed: 6,401 widths, exact boundaries, and expand/collapse state changes.")
    }

    private static func changes(in widths: [CGFloat]) -> Int {
        let controls = widths.map(PlayerBarControlVisibility.init(width:))
        return zip(controls, controls.dropFirst()).filter { $0 != $1 }.count
    }
}
