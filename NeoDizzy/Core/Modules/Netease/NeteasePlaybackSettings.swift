// Quality levels and fallback order adapted from MeloX (GPL-3.0).
import Foundation
import Network
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
    var wifi: NeteaseQuality {
        didSet { defaults.set(wifi.rawValue, forKey: "netease.quality.wifi"); if oldValue != wifi && !isCellular { changed?() } }
    }
    var cellular: NeteaseQuality {
        didSet { defaults.set(cellular.rawValue, forKey: "netease.quality.cellular"); if oldValue != cellular && isCellular { changed?() } }
    }
    var download: NeteaseQuality {
        didSet { defaults.set(download.rawValue, forKey: "netease.quality.download") }
    }
    private(set) var isCellular = false
    var selected: NeteaseQuality { isCellular ? cellular : wifi }
    @ObservationIgnored var changed: (() -> Void)?
    @ObservationIgnored private let defaults: UserDefaults
    @ObservationIgnored private let monitor: NWPathMonitor?

    init(defaults: UserDefaults = .standard, monitorsNetwork: Bool = true) {
        self.defaults = defaults
        download = NeteaseQuality(rawValue: defaults.string(forKey: "netease.quality.download") ?? "") ?? .lossless
        wifi = NeteaseQuality(rawValue: defaults.string(forKey: "netease.quality.wifi") ?? "") ?? .high
        cellular = NeteaseQuality(rawValue: defaults.string(forKey: "netease.quality.cellular") ?? "") ?? .high
        monitor = monitorsNetwork ? NWPathMonitor() : nil
        monitor?.pathUpdateHandler = { [weak self] path in
            let cellular = path.usesInterfaceType(.cellular)
            Task { @MainActor [weak self] in self?.updateNetwork(isCellular: cellular) }
        }
        monitor?.start(queue: DispatchQueue(label: "NeoDizzy.Netease.Network"))
    }
    func updateNetwork(isCellular: Bool) {
        guard self.isCellular != isCellular else { return }
        self.isCellular = isCellular
        changed?()
    }
    deinit { monitor?.cancel() }
}
