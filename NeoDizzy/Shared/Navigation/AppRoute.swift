import Foundation

/// Stable namespace owned by a module, independent of the tab slot displaying it.
struct ModuleID: RawRepresentable, Hashable, Codable, Identifiable, Sendable {
    let rawValue: String
    var id: String { rawValue }
    nonisolated init(rawValue: String) { self.rawValue = rawValue }

    /// 标签栏右侧的统一搜索；它有自己的导航路径，但不是模块。
    static let search = ModuleID(rawValue: "search")
}

/// The host transports routes without knowing their module-specific payload types.
struct AppRoute: Hashable {
    let moduleID: ModuleID
    let destination: AnyHashable
    let title: String
    /// Transient presentation identity, independent of the module's business payload.
    /// Distinct card occurrences remain distinct entries, including nested navigation.
    private(set) var zoomSourceID: UUID? = nil

    init<Destination: Hashable>(moduleID: ModuleID, destination: Destination, title: String) {
        self.moduleID = moduleID
        self.destination = AnyHashable(destination)
        self.title = title
    }

    func zooming(from sourceID: UUID) -> Self {
        var route = self
        route.zoomSourceID = sourceID
        return route
    }
}
