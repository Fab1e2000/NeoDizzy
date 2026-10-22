import Foundation
import Observation

struct ModulePreferences {
    var order: [ModuleID]
    var hidden: Set<ModuleID>
    var startup: ModuleID
}

/// Persists installed module identities. Provider metadata and legacy migration are injected.
@Observable
final class ModuleSettings {
    private(set) var order: [ModuleID]
    private(set) var searchOrder: [ModuleID]
    private(set) var hidden: Set<ModuleID>
    var startupModule: ModuleID { didSet { save() } }
    @ObservationIgnored private let installed: [ModuleID]
    @ObservationIgnored private let defaults: UserDefaults
    private static let key = "mainModules.v1"
    private static let searchKey = "search.moduleOrder.v1"
    private struct Snapshot: Codable {
        var order: [String]
        var hidden: [String]
        var startup: String
    }

    init(modules: [ModuleDescriptor], defaults: UserDefaults = .standard, legacy: ModulePreferences? = nil) {
        let ids = modules.map(\.id)
        precondition(!ids.isEmpty && Set(ids).count == ids.count, "Register at least one module with unique IDs")
        self.installed = ids
        self.defaults = defaults
        let preferences: ModulePreferences
        if let data = defaults.data(forKey: Self.key),
           let snapshot = try? JSONDecoder().decode(Snapshot.self, from: data) {
            preferences = ModulePreferences(order: snapshot.order.map { ModuleID(rawValue: $0) },
                                            hidden: Set(snapshot.hidden.map { ModuleID(rawValue: $0) }),
                                            startup: ModuleID(rawValue: snapshot.startup))
        } else {
            preferences = legacy ?? ModulePreferences(order: ids, hidden: [], startup: ids[0])
        }
        var seen = Set<ModuleID>()
        let moduleOrder = (preferences.order + ids).filter { ids.contains($0) && seen.insert($0).inserted }
        order = moduleOrder
        let savedSearch = defaults.stringArray(forKey: Self.searchKey)?.map { ModuleID(rawValue: $0) }
        let defaultSearch = moduleOrder.filter { $0 == .localLibrary } + moduleOrder.filter { $0 != .localLibrary }
        var searchSeen = Set<ModuleID>()
        searchOrder = ((savedSearch ?? defaultSearch) + ids).filter { ids.contains($0) && searchSeen.insert($0).inserted }
        hidden = preferences.hidden.intersection(ids)
        startupModule = ids.contains(preferences.startup) ? preferences.startup : ids[0]
        if order.allSatisfy(hidden.contains), let first = order.first { hidden.remove(first) }
        save()
    }

    var visibleSearchModules: [ModuleID] { searchOrder.filter(isVisible) }
    func reorderSearch(_ modules: [ModuleID]) {
        guard modules.count == installed.count, Set(modules) == Set(installed) else { return }
        searchOrder = modules
        save()
    }
    func resetSearchOrder() {
        reorderSearch(installed.filter { $0 == .localLibrary } + installed.filter { $0 != .localLibrary })
    }

    var visibleModules: [ModuleID] { order.filter(isVisible) }
    var initialModule: ModuleID { isVisible(startupModule) ? startupModule : visibleModules[0] }
    func isVisible(_ module: ModuleID) -> Bool { installed.contains(module) && !hidden.contains(module) }
    func canHide(_ module: ModuleID) -> Bool { installed.contains(module) && (!isVisible(module) || visibleModules.count > 1) }
    func setVisible(_ visible: Bool, for module: ModuleID) {
        guard installed.contains(module) else { return }
        if visible { hidden.remove(module) }
        else if canHide(module) { hidden.insert(module) }
        save()
    }
    func reorder(_ modules: [ModuleID]) {
        guard modules.count == installed.count, Set(modules) == Set(installed) else { return }
        order = modules
        save()
    }
    func reset() { order = installed; hidden = []; save() }
    /// 从配置文件恢复：未安装的模块忽略，新装的模块补在末尾，至少留一个可见。
    func restore(order: [ModuleID], hidden: Set<ModuleID>, startup: ModuleID, search: [ModuleID]) {
        var seen = Set<ModuleID>(), searchSeen = Set<ModuleID>()
        self.order = (order + installed).filter { installed.contains($0) && seen.insert($0).inserted }
        searchOrder = (search + searchOrder).filter { installed.contains($0) && searchSeen.insert($0).inserted }
        self.hidden = hidden.intersection(installed)
        if self.order.allSatisfy(self.hidden.contains), let first = self.order.first { self.hidden.remove(first) }
        startupModule = installed.contains(startup) ? startup : installed[0]
        save()
    }
    private func save() {
        defaults.set(searchOrder.map(\.rawValue), forKey: Self.searchKey)
        let snapshot = Snapshot(order: order.map(\.rawValue), hidden: hidden.map(\.rawValue), startup: startupModule.rawValue)
        if let data = try? JSONEncoder().encode(snapshot) { defaults.set(data, forKey: Self.key) }
    }
}
