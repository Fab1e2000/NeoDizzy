import Foundation

nonisolated struct BrowsedDisc: Codable, Identifiable, Equatable, Sendable {
    let id: String
    var title: String
    var labelName: String?
    var coverURL: URL?
    var visitedAt: Date
}

/// 仅由专辑详情页记录；不保存播放地址、购买权限或账号凭据。
@Observable
final class BrowsingHistoryStore {
    private(set) var entries: [BrowsedDisc]
    private let defaults: UserDefaults
    private let key = "browsedDiscs.v1"
    private let limit = 200

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        let saved = defaults.data(forKey: key).flatMap { try? JSONDecoder().decode([BrowsedDisc].self, from: $0) } ?? []
        var ids = Set<String>()
        entries = Array(saved.sorted { $0.visitedAt > $1.visitedAt }.filter { ids.insert($0.id).inserted }.prefix(200))
    }

    func visit(id: String, summary: DiscSummary?, at date: Date = .now) {
        var entry = entries.first { $0.id == id }
            ?? BrowsedDisc(id: id, title: id, visitedAt: date)
        entry.visitedAt = date
        if let summary, summary.id == id {
            entry.title = summary.title
            entry.labelName = summary.labelName
            entry.coverURL = summary.coverURL
        }
        entries.removeAll { $0.id == id }
        entries.insert(entry, at: 0)
        entries = Array(entries.prefix(limit))
        save()
    }

    /// 网络详情稍后到达时补全信息，不产生一次新的访问，也不恢复已删除的记录。
    func update(_ summary: DiscSummary) {
        guard let index = entries.firstIndex(where: { $0.id == summary.id }) else { return }
        entries[index].title = summary.title
        entries[index].labelName = summary.labelName
        entries[index].coverURL = summary.coverURL
        save()
    }

    func remove(ids: Set<String>) {
        entries.removeAll { ids.contains($0.id) }
        save()
    }

    func clear() {
        entries = []
        defaults.removeObject(forKey: key)
    }

    private func save() {
        guard let data = try? JSONEncoder().encode(entries) else { return }
        defaults.set(data, forKey: key)
    }
}
