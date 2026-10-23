import Foundation
import Observation

/// 资料库里来自平台账号的专辑或歌单。
nonisolated struct MirroredCollection: Codable, Hashable, Identifiable, Sendable {
    enum Kind: String, Codable, Sendable { case album, playlist }

    let providerID: String
    let kind: Kind
    let itemID: String
    let title: String
    let subtitle: String
    let coverURL: URL?
    /// 网易云账号自带的「我喜欢的音乐」。
    var isLikedPlaylist = false
    /// 自己创建的歌单或已购专辑：不能从账号里取消，只能在平台上管理。
    var isPermanent = false
    /// 第一次同步到这一项的时间，用于「最近添加」。
    var firstSeen: Date

    var id: String { "\(providerID)/\(kind.rawValue)/\(itemID)" }
}

/// Account snapshots are independent namespaces; unavailable providers retain their data on disk.
@Observable @MainActor final class AccountLibraryMirror {
    struct State: Codable {
        var account: String?
        var collections: [MirroredCollection] = []
        var legacyLikes: [Track] = []
        var artistIDs: [String: String] = [:]
        var artistAvatars: [String: URL] = [:]
    }
    struct Snapshot: Codable {
        var providers: [String: State] = [:]
        var firstSeen: [String: Date] = [:]
    }
    var snapshot = Snapshot()
    @ObservationIgnored private let fileURL: URL
    @ObservationIgnored private var tasks: [String: Task<Void, Error>] = [:]
    @ObservationIgnored private var generations: [String: Int] = [:]
    private var refreshers: [String: (Bool) async throws -> Void] = [:]
    private var accounts: [String: () -> String?] = [:]
    @ObservationIgnored var legacyCollectionLoader: ((String) async throws -> [MirroredCollection])?
    @ObservationIgnored var avatarRequests = Set<String>()
    private(set) var syncing = Set<String>()
    var isSyncing: Bool { !syncing.isEmpty }
    var collections: [MirroredCollection] {
        refreshers.keys.sorted().flatMap { provider -> [MirroredCollection] in
            let saved = state(provider)
            if let account = accounts[provider], account() != saved.account { return [] }
            return saved.collections
        }
    }
    init(directory: URL = URL.applicationSupportDirectory.appendingPathComponent("Library", isDirectory: true)) {
        fileURL = directory.appendingPathComponent("account-mirror.json")
        if let data = try? Data(contentsOf: fileURL) {
            if let saved = try? JSONDecoder().decode(Snapshot.self, from: data) { snapshot = saved }
            else { snapshot = Self.migrateLegacy(data) }
        }
    }
    func register(_ provider: String, account: (() -> String?)? = nil,
                  refresh: @escaping (Bool) async throws -> Void) {
        accounts[provider] = account
        if let account { reconcileAccount(provider, account: account()) }
        refreshers[provider] = refresh
    }
    func unregister(_ provider: String) {
        refreshers[provider] = nil
        accounts[provider] = nil
        generations[provider, default: 0] += 1
        tasks.removeValue(forKey: provider)?.cancel()
        syncing.remove(provider)
    }
    func refresh(force: Bool) async {
        // A slow or failing service must not prevent the other sources from synchronizing.
        let work = refreshers.keys.sorted().map { id in
            Task { try? await self.refreshers[id]?(force) }
        }
        for task in work { await task.value }
    }
    func generation(for provider: String) -> Int { generations[provider, default: 0] }
    func state(_ provider: String) -> State { snapshot.providers[provider] ?? State() }
    /// Reconcile synchronously before a newly registered source can expose its cached collections.
    func reconcileAccount(_ provider: String, account: String?) {
        if state(provider).account != account {
            generations[provider, default: 0] += 1
            tasks.removeValue(forKey: provider)?.cancel()
            syncing.remove(provider)
            snapshot.providers[provider] = State(account: account)
            save()
        }
    }
    func sync(_ provider: String, account: String?, operation: @escaping (@escaping ([MirroredCollection]) throws -> Void) async throws -> Void) async throws {
        reconcileAccount(provider, account: account)
        guard account != nil else { return }
        if let task = tasks[provider] { return try await task.value }
        let generation = generations[provider, default: 0]
        syncing.insert(provider)
        let task = Task {
            try await operation { items in
                try Task.checkCancellation()
                guard self.generations[provider, default: 0] == generation else { throw CancellationError() }
                self.replace(provider, collections: items)
            }
        }
        tasks[provider] = task
        defer {
            if generations[provider, default: 0] == generation { tasks[provider] = nil; syncing.remove(provider) }
        }
        try await task.value
    }
    func replace(_ provider: String, collections: [MirroredCollection]) {
        snapshot.providers[provider, default: State()].collections = collections.filter { $0.providerID == provider }
        save()
    }
    func item(providerID: String, kind: MirroredCollection.Kind, itemID: String, title: String, subtitle: String,
              coverURL: URL?, isLikedPlaylist: Bool = false, isPermanent: Bool = false) -> MirroredCollection {
        let key = "\(providerID)/\(kind.rawValue)/\(itemID)"
        let firstSeen = snapshot.firstSeen[key] ?? .now
        snapshot.firstSeen[key] = firstSeen
        return MirroredCollection(providerID: providerID, kind: kind, itemID: itemID, title: title, subtitle: subtitle,
                                  coverURL: coverURL, isLikedPlaylist: isLikedPlaylist, isPermanent: isPermanent, firstSeen: firstSeen)
    }
    func save() {
        do {
            try FileManager.default.createDirectory(at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
            try JSONEncoder().encode(snapshot).write(to: fileURL, options: .atomic)
        } catch { assertionFailure("Saving account mirror failed: \(error)") }
    }
}

/// 多人署名按逗号、斜杠和顿号拆开。
nonisolated enum LibraryArtistNames {
    static func split(_ artists: String) -> [String] {
        artists.split(whereSeparator: { ",，/、".contains($0) })
            .map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
    }
}
