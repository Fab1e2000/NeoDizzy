import Foundation
import Observation

/// 资料库里的一个在线条目：歌曲保存可直接播放的 `Track`，专辑与歌单只保存打开它所需的身份。
/// 本地文件不进这里，由 `OfflineLibraryStore` 扫描得到。
nonisolated struct SavedLibraryItem: Codable, Hashable, Identifiable, Sendable {
    enum Kind: String, Codable, Sendable { case song, album, playlist }

    let kind: Kind
    /// `netease`、`dizzylab` 等，与下载和远程曲目使用同一命名。
    let providerID: String
    let itemID: String
    let title: String
    /// 歌手、作者或社团。
    let subtitle: String
    let coverURL: URL?
    var track: Track?
    let addedAt: Date

    var id: String { Self.id(kind: kind, providerID: providerID, itemID: itemID) }

    static func id(kind: Kind, providerID: String, itemID: String) -> String {
        "\(kind.rawValue)/\(providerID)/\(itemID)"
    }

    static func song(_ track: Track, providerID: String, itemID: String, addedAt: Date = .now) -> Self {
        Self(kind: .song, providerID: providerID, itemID: itemID, title: track.title, subtitle: track.artists,
             coverURL: track.coverURL, track: track, addedAt: addedAt)
    }
}

/// 用户手动「加入资料库」的在线歌曲、专辑和歌单，保存在 App 内，不改动任何平台账号。
@Observable
@MainActor
final class SavedLibraryStore {
    private(set) var items: [SavedLibraryItem] = []
    var persistenceError: String?
    @ObservationIgnored private var pendingItems: [SavedLibraryItem]?
    @ObservationIgnored private let writeData: (Data, URL) throws -> Void
    @ObservationIgnored private let fileURL: URL

    init(directory: URL = URL.applicationSupportDirectory.appendingPathComponent("Library", isDirectory: true), writeData: @escaping (Data, URL) throws -> Void = { try $0.write(to: $1, options: .atomic) }) {
        self.writeData = writeData
        fileURL = directory.appendingPathComponent("saved-items.json")
        if let data = try? Data(contentsOf: fileURL),
           let saved = try? JSONDecoder().decode([SavedLibraryItem].self, from: data) {
            items = saved
        }
    }

    func contains(_ kind: SavedLibraryItem.Kind, providerID: String, itemID: String) -> Bool {
        let id = SavedLibraryItem.id(kind: kind, providerID: providerID, itemID: itemID)
        return items.contains { $0.id == id }
    }

    func items(of kind: SavedLibraryItem.Kind) -> [SavedLibraryItem] {
        items.filter { $0.kind == kind }
    }

    /// Publish changes only after the atomic snapshot succeeds.
    @discardableResult
    func add(_ item: SavedLibraryItem) -> Bool {
        guard !items.contains(where: { $0.id == item.id }) else { return true }
        return save([item] + items)
    }

    @discardableResult
    func remove(id: String) -> Bool { save(items.filter { $0.id != id }) }

    @discardableResult
    func toggle(_ item: SavedLibraryItem) -> Bool {
        if items.contains(where: { $0.id == item.id }) { return remove(id: item.id) }
        return add(item)
    }

    func removeMigratedSongs(ids: Set<String>) throws {
        guard !ids.isEmpty else { return }
        try persist(items.filter { !ids.contains($0.id) })
    }

    private func persist(_ candidate: [SavedLibraryItem]) throws {
        try FileManager.default.createDirectory(at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        try writeData(JSONEncoder().encode(candidate), fileURL)
        items = candidate
        persistenceError = nil
        pendingItems = nil
    }

    @discardableResult
    func retryPersistence() -> Bool {
        guard let pendingItems else { return true }
        return save(pendingItems)
    }

    private func save(_ candidate: [SavedLibraryItem]) -> Bool {
        do {
            try persist(candidate)
            return true
        } catch {
            pendingItems = candidate
            persistenceError = "资料库更改未保存，请重试。"
            return false
        }
    }
}
