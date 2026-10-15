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
    @ObservationIgnored private let fileURL: URL

    init(directory: URL = URL.applicationSupportDirectory.appendingPathComponent("Library", isDirectory: true)) {
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

    /// 已在资料库时不重复添加，保留原来的加入时间。
    func add(_ item: SavedLibraryItem) {
        guard !items.contains(where: { $0.id == item.id }) else { return }
        items.insert(item, at: 0)
        save()
    }

    func remove(id: String) {
        items.removeAll { $0.id == id }
        save()
    }

    func toggle(_ item: SavedLibraryItem) {
        if items.contains(where: { $0.id == item.id }) { remove(id: item.id) } else { add(item) }
    }

    private func save() {
        do {
            try FileManager.default.createDirectory(at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
            try JSONEncoder().encode(items).write(to: fileURL, options: .atomic)
        } catch {
            assertionFailure("Saving the library index failed: \(error)")
        }
    }
}
