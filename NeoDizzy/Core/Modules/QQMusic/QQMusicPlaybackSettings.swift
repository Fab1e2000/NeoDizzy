import Foundation
import Observation

/// Native, taggable formats from L-1124/QQMusicApi SongFileType.
nonisolated enum QQMusicQuality: String, CaseIterable, Identifiable, Codable, Sendable {
    case standard = "mp3_128", high = "mp3_320", lossless = "flac", master = "master"
    var id: String { rawValue }
    var title: String {
        switch self {
        case .standard: "标准 · 128 kbps"
        case .high: "高品质 · 320 kbps"
        case .lossless: "无损 · FLAC"
        case .master: "臻品母带 · FLAC"
        }
    }
    var prefix: String {
        switch self {
        case .standard: "M500"
        case .high: "M800"
        case .lossless: "F000"
        case .master: "AI00"
        }
    }
    var fileExtension: String { self == .standard || self == .high ? "mp3" : "flac" }
    var fallbacks: [Self] {
        switch self {
        case .standard: [.standard]
        case .high: [.high, .standard]
        case .lossless: [.lossless, .high, .standard]
        case .master: [.master, .lossless, .high, .standard]
        }
    }
}

@Observable @MainActor final class QQMusicPlaybackSettings {
    var quality: QQMusicQuality {
        didSet {
            defaults.set(quality.rawValue, forKey: "qqmusic.quality.unified")
            if oldValue != quality { changed?() }
        }
    }
    @ObservationIgnored var changed: (() -> Void)?
    @ObservationIgnored private let defaults: UserDefaults
    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        quality = defaults.string(forKey: "qqmusic.quality.unified").flatMap(QQMusicQuality.init(rawValue:)) ?? .high
    }
}
