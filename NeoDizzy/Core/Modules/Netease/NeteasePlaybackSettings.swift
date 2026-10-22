// Quality levels and fallback order adapted from MeloX (GPL-3.0).
import Foundation
import Observation

nonisolated enum NeteaseQuality: String, CaseIterable, Identifiable, Codable, Sendable {
    case standard, high = "exhigh", lossless, hiResolution = "hires"
    case surround = "jyeffect", immersive = "sky", master = "jymaster"
    var id: String { rawValue }
    var title: String {
        switch self {
        case .standard: "标准"
        case .high: "高品质"
        case .lossless: "无损"
        case .hiResolution: "Hi-Res"
        case .surround: "高清臻音"
        case .immersive: "沉浸环绕声"
        case .master: "超清母带"
        }
    }
    var fallbacks: [Self] {
        switch self {
        case .standard: [.standard]
        case .high: [.high, .standard]
        case .lossless: [.lossless, .high, .standard]
        case .hiResolution: [.hiResolution, .lossless, .high, .standard]
        case .surround: [.surround, .lossless, .high, .standard]
        case .immersive: [.immersive, .surround, .lossless, .high, .standard]
        case .master: [.master, .hiResolution, .lossless, .high, .standard]
        }
    }
}

@Observable final class NeteasePlaybackSettings {
    var quality: NeteaseQuality {
        didSet {
            defaults.set(quality.rawValue, forKey: "netease.quality.unified")
            if oldValue != quality { changed?() }
        }
    }
    var selected: NeteaseQuality { quality }
    @ObservationIgnored var changed: (() -> Void)?
    @ObservationIgnored private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        // Preserve the previous Wi-Fi playback choice on upgrade; new installs use high quality.
        quality = NeteaseQuality(rawValue: defaults.string(forKey: "netease.quality.unified")
            ?? defaults.string(forKey: "netease.quality.wifi") ?? "") ?? .high
    }
}
