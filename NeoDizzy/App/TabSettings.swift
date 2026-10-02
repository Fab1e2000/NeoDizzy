import Foundation
import Observation

@Observable
final class TabSettings {
    private(set) var order: [MainTab]
    private(set) var hidden: Set<MainTab>
    @ObservationIgnored private let defaults: UserDefaults
    var startupTab: MainTab {
        didSet { defaults.set(startupTab.rawValue, forKey: "mainTabs.startup") }
    }
    var initialTab: MainTab { isVisible(startupTab) ? startupTab : visiblePrimary[0] }
    private static let key = "mainTabs.v1"
    private struct Snapshot: Codable {
        var order: [String]
        var hidden: [String]
    }

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        startupTab = defaults.string(forKey: "mainTabs.startup").flatMap(MainTab.init(rawValue:)) ?? .discover
        let snapshot = defaults.data(forKey: Self.key).flatMap { try? JSONDecoder().decode(Snapshot.self, from: $0) }
        var seen = Set<MainTab>()
        order = ((snapshot?.order.compactMap(MainTab.init(rawValue:)) ?? []) + MainTab.primary)
            .filter { seen.insert($0).inserted }
        hidden = Set(snapshot?.hidden.compactMap(MainTab.init(rawValue:)) ?? [])
        if order.allSatisfy({ hidden.contains($0) }) { hidden.remove(order[0]) }
    }

    var visiblePrimary: [MainTab] { order.filter(isVisible) }
    var visibleTabs: [MainTab] { visiblePrimary }
    func isVisible(_ tab: MainTab) -> Bool { !hidden.contains(tab) }
    func canHide(_ tab: MainTab) -> Bool { !isVisible(tab) || visiblePrimary.count > 1 }

    func setVisible(_ visible: Bool, for tab: MainTab) {
        if visible { hidden.remove(tab) }
        else if canHide(tab) { hidden.insert(tab) }
        save()
    }

    func reorder(_ tabs: [MainTab]) {
        guard tabs.count == MainTab.primary.count, Set(tabs) == Set(MainTab.primary) else { return }
        order = tabs
        save()
    }

    func reset() { order = MainTab.primary; hidden = []; save() }
    private func save() {
        if let data = try? JSONEncoder().encode(Snapshot(order: order.map(\.rawValue), hidden: hidden.map(\.rawValue))) {
            defaults.set(data, forKey: Self.key)
        }
    }
}
