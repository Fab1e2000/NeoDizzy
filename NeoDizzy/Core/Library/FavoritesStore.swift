import Foundation
import Observation
import SQLite3

/// 平台 + 歌曲身份，不按标题去重。下载的在线歌曲仍保留原平台身份。
nonisolated struct FavoriteSong: Codable, Identifiable, Equatable {
    let providerID: String
    let itemID: String
    let track: Track
    var addedAt: Date?
    var id: String { "\(providerID)/\(itemID)" }
    init(track: Track, addedAt: Date? = nil) {
        self.track = track
        self.addedAt = addedAt
        providerID = track.remoteSource?.providerID ?? (track.localSource == nil ? "dizzylab" : "local")
        itemID = track.remoteSource?.itemID ?? track.localSource?.trackID ?? track.id
    }
}

/// 注册平台只提供账号、读列表和写喜欢；资料库不依赖平台页面。
@MainActor struct FavoritesProvider {
    let account: () -> String?
    let load: () async throws -> [Track]
    let setLiked: (Track, Bool) async throws -> Void
}

@Observable @MainActor final class FavoritesStore {
    private(set) var records: [String: [FavoriteSong]] = [:]
    private(set) var pending = Set<String>()
    private(set) var syncing = Set<String>()
    private(set) var errors: [String: String] = [:]
    private var accounts: [String: String] = [:]
    @ObservationIgnored private var providers: [String: FavoritesProvider] = [:]
    @ObservationIgnored private var versions: [String: Int] = [:]
    @ObservationIgnored private let fileURL: URL

    init(directory: URL = URL.applicationSupportDirectory.appendingPathComponent("Library", isDirectory: true)) {
        fileURL = directory.appendingPathComponent("favorites.sqlite")
        do {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            try database { db in
                guard sqlite3_exec(db, "CREATE TABLE IF NOT EXISTS favorites (scope TEXT PRIMARY KEY, payload BLOB NOT NULL)", nil, nil, nil) == SQLITE_OK else { throw StorageError.failed }
                var statement: OpaquePointer?
                guard sqlite3_prepare_v2(db, "SELECT scope, payload FROM favorites", -1, &statement, nil) == SQLITE_OK else { throw StorageError.failed }
                defer { sqlite3_finalize(statement) }
                while sqlite3_step(statement) == SQLITE_ROW {
                    let scope = String(cString: sqlite3_column_text(statement, 0))
                    let size = Int(sqlite3_column_bytes(statement, 1))
                    if let bytes = sqlite3_column_blob(statement, 1) {
                        records[scope] = try JSONDecoder().decode([FavoriteSong].self, from: Data(bytes: bytes, count: size))
                    }
                }
            }
        } catch { errors["storage"] = error.localizedDescription }
    }

    var songs: [FavoriteSong] {
        let scopes = ["device"] + accounts.map { "\($0.key)/\($0.value)" }.sorted()
        // 各来源内部严格保留接口顺序；只比较每个列表的首项来合并来源。
        // 新喜欢插入来源列表首位，其时间也使它成为统一列表的第一项。
        let lists = scopes.map { records[$0] ?? [] }
        var offsets = Array(repeating: 0, count: lists.count)
        var result: [FavoriteSong] = []
        while let index = lists.indices.filter({ offsets[$0] < lists[$0].count }).max(by: {
            let lhs = lists[$0][offsets[$0]].addedAt ?? .distantPast
            let rhs = lists[$1][offsets[$1]].addedAt ?? .distantPast
            return lhs == rhs ? $0 > $1 : lhs < rhs
        }) {
            result.append(lists[index][offsets[index]])
            offsets[index] += 1
        }
        return result
    }

    /// 升级时导入已有喜欢缓存；已有数据库（包括空列表）绝不被旧缓存覆盖。
    func migrate(providerID: String, account: String, tracks: [Track]) {
        let scope = "\(providerID)/\(account)"
        guard records[scope] == nil else { return }
        do { try replace(scope: scope, values: tracks.map { FavoriteSong(track: $0) }.filter { $0.providerID == providerID }) }
        catch { errors["storage"] = error.localizedDescription }
    }
    /// 数据和迁移标记在同一事务提交；清理旧文件失败也不会复活已取消的喜欢。
    func migrateSavedSongs(from saved: SavedLibraryStore) {
        let marker = "migration/dizzylab-saved-songs-v1"
        let candidates = saved.items(of: .song).filter { $0.providerID == "dizzylab" && $0.track != nil }
        do {
            if records[marker] == nil {
                let imported = candidates.compactMap { item -> FavoriteSong? in
                    guard let track = item.track else { return nil }
                    let song = FavoriteSong(track: track, addedAt: item.addedAt)
                    return song.providerID == "dizzylab" ? song : nil
                }
                var seen = Set<String>()
                let merged = ((records["device"] ?? []) + imported)
                    .filter { seen.insert($0.id).inserted }
                    .sorted { ($0.addedAt ?? .distantPast) > ($1.addedAt ?? .distantPast) }
                try database { db in
                    guard sqlite3_exec(db, "BEGIN IMMEDIATE", nil, nil, nil) == SQLITE_OK else { throw StorageError.failed }
                    do {
                        try persist(scope: "device", values: merged, db: db)
                        try persist(scope: marker, values: imported, db: db)
                        guard sqlite3_exec(db, "COMMIT", nil, nil, nil) == SQLITE_OK else { throw StorageError.failed }
                    } catch {
                        sqlite3_exec(db, "ROLLBACK", nil, nil, nil)
                        throw error
                    }
                }
                records["device"] = merged
                records[marker] = imported
            }
            let importedIDs = Set((records[marker] ?? []).map(\.id))
            let removeIDs = Set(candidates.filter { item in
                item.track.map { importedIDs.contains(FavoriteSong(track: $0).id) } ?? false
            }.map(\.id))
            try saved.removeMigratedSongs(ids: removeIDs)
        } catch { errors["storage"] = error.localizedDescription }
    }
    /// 从配置文件恢复本机喜欢（本地与 DizzyLab）：只补上没有的，保留现有顺序与时间。
    /// 返回新增数量。
    func importDeviceSongs(_ songs: [FavoriteSong]) throws -> Int {
        let existing = records["device"] ?? []
        let known = Set(existing.map(\.id))
        var seen = known
        let added = songs.filter { seen.insert($0.id).inserted }
        guard !added.isEmpty else { return 0 }
        let merged = (existing + added).sorted { ($0.addedAt ?? .distantPast) > ($1.addedAt ?? .distantPast) }
        try replace(scope: "device", values: merged)
        return added.count
    }
    /// 导入备份时没对上音乐文件的本地喜欢：不显示，但继续写进之后的备份，放回音乐再导入时还能恢复。
    static let unmatchedLocalScope = "restore/unmatched-local"
    var unmatchedLocal: [FavoriteSong] { records[Self.unmatchedLocalScope] ?? [] }
    func setUnmatchedLocal(_ songs: [FavoriteSong]) throws {
        guard !(songs.isEmpty && records[Self.unmatchedLocalScope] == nil) else { return }
        try replace(scope: Self.unmatchedLocalScope, values: songs)
    }
    /// 账号喜欢的已知时间。平台的喜欢列表不带时间，重装、换号后重新同步会把整个列表记成「刚刚」，
    /// 把本机的喜欢挤到最后；这里记下备份里的时间，同步时沿用。
    static let knownTimesScope = "restore/account-times"
    /// 从备份恢复账号喜欢的时间：记下来供之后同步使用，已经同步过的列表取较早的时间。
    func restoreAccountTimes(_ songs: [FavoriteSong]) throws {
        var known = Dictionary((records[Self.knownTimesScope] ?? []).map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        var times: [String: Date] = [:]
        for song in songs {
            guard let time = song.addedAt else { continue }
            times[song.id] = min(time, times[song.id] ?? time)
            if (known[song.id]?.addedAt ?? .distantFuture) > time { known[song.id] = song }
        }
        guard !times.isEmpty else { return }
        try replace(scope: Self.knownTimesScope, values: known.values.sorted { $0.id < $1.id })
        for scope in records.keys where scope.contains("/") && !scope.hasPrefix("restore/") && !scope.hasPrefix("migration/") {
            guard var values = records[scope] else { continue }
            var changed = false
            for index in values.indices {
                if let time = times[values[index].id], time < (values[index].addedAt ?? .distantFuture) {
                    values[index].addedAt = time; changed = true
                }
            }
            if changed { try replace(scope: scope, values: values) }
        }
    }
    func contains(_ track: Track) -> Bool { songs.contains { $0.id == FavoriteSong(track: track).id } }
    func register(_ id: String, provider: FavoritesProvider) {
        providers[id] = provider
        updateAccounts()
    }
    func updateAccounts() {
        for (id, provider) in providers {
            let account = provider.account()
            if accounts[id] != account { versions[id, default: 0] += 1; errors[id] = nil }
            accounts[id] = account
        }
    }
    func refresh() async {
        updateAccounts()
        for id in providers.keys.sorted() { await refresh(id) }
    }
    func refresh(_ id: String) async {
        updateAccounts()
        guard let provider = providers[id], let account = accounts[id], !syncing.contains(id) else { return }
        syncing.insert(id)
        defer {
            syncing.remove(id)
            if accounts[id] != account, accounts[id] != nil {
                Task { await self.refresh(id) }
            }
        }
        do {
            // 若读列表期间发生写入，丢弃旧读取，再读一次，避免覆盖新喜欢状态。
            while accounts[id] == account {
                let version = versions[id, default: 0]
                let tracks = try await provider.load()
                try Task.checkCancellation()
                updateAccounts()
                guard accounts[id] == account else { return }
                guard versions[id, default: 0] == version else { continue }
                let values = tracks.map { FavoriteSong(track: $0) }.filter { $0.providerID == id }
                try replace(scope: "\(id)/\(account)", values: values)
                errors[id] = nil
                return
            }
        } catch is CancellationError {
        } catch { if accounts[id] == account { errors[id] = error.localizedDescription } }
    }
    func setLiked(_ track: Track, _ liked: Bool) async throws {
        updateAccounts()
        let song = FavoriteSong(track: track, addedAt: .now)
        guard pending.insert(song.id).inserted else { return }
        defer { pending.remove(song.id) }
        let scope: String
        if let provider = providers[song.providerID] {
            guard let account = accounts[song.providerID] else { throw StorageError.loginRequired }
            let version = versions[song.providerID, default: 0]
            try await provider.setLiked(track, liked)
            updateAccounts()
            guard accounts[song.providerID] == account else { throw CancellationError() }
            // Other writes are allowed, account changes are checked above.
            versions[song.providerID] = max(version, versions[song.providerID, default: 0]) + 1
            scope = "\(song.providerID)/\(account)"
        } else {
            guard song.providerID == "local" || song.providerID == "dizzylab" else { throw StorageError.unsupported }
            scope = "device"
        }
        var values = records[scope] ?? []
        values.removeAll { $0.id == song.id }
        if liked { values.insert(song, at: 0) }
        try replace(scope: scope, values: values)
    }
    private func replace(scope: String, values: [FavoriteSong]) throws {
        var seen = Set<String>()
        let previous = Dictionary((records[scope] ?? []).map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        let known = Dictionary((records[Self.knownTimesScope] ?? []).map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        // 列表按喜欢的先后排列：时间未知的歌紧跟在前一首后面，而不是一律记成现在。
        var last = Date.now
        let unique = values.filter { seen.insert($0.id).inserted }.map { value in
            var result = value
            if result.addedAt == nil {
                result.addedAt = previous[value.id].map { $0.addedAt ?? .distantPast }
                    ?? known[value.id]?.addedAt ?? last.addingTimeInterval(-0.001)
            }
            last = min(last, result.addedAt ?? last)
            return result
        }
        try database { db in try persist(scope: scope, values: unique, db: db) }
        records[scope] = unique
    }
    private func persist(scope: String, values: [FavoriteSong], db: OpaquePointer) throws {
        let data = try JSONEncoder().encode(values)
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(db, "INSERT OR REPLACE INTO favorites (scope, payload) VALUES (?, ?)", -1, &statement, nil) == SQLITE_OK else { throw StorageError.failed }
        defer { sqlite3_finalize(statement) }
        let transient = unsafeBitCast(-1, to: sqlite3_destructor_type.self)
        _ = scope.withCString { sqlite3_bind_text(statement, 1, $0, -1, transient) }
        _ = data.withUnsafeBytes { sqlite3_bind_blob(statement, 2, $0.baseAddress, Int32($0.count), transient) }
        guard sqlite3_step(statement) == SQLITE_DONE else { throw StorageError.failed }
    }
    private func database<T>(_ operation: (OpaquePointer) throws -> T) throws -> T {
        var db: OpaquePointer?
        let status = sqlite3_open(fileURL.path, &db)
        defer { if let db { sqlite3_close(db) } }
        guard status == SQLITE_OK, let db else { throw StorageError.failed }
        return try operation(db)
    }
    private enum StorageError: LocalizedError {
        case failed, loginRequired, unsupported
        var errorDescription: String? {
            switch self {
            case .failed: "无法保存喜欢的音乐，请检查本机存储空间后重试。"
            case .loginRequired: "请先登录歌曲所属平台。"
            case .unsupported: "这个音乐来源尚未接入喜欢功能。"
            }
        }
    }
}
