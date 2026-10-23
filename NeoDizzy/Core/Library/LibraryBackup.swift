import Foundation
import Observation

#if os(iOS)
/// 「文件 › 我的 iPhone › NeoDizzy › Backup」里唯一的一份资料库备份。
/// 重签名的 App 拿不到外部文件的访问权，所以备份只写在自己的文件夹里：
/// 卸载前把 Backup 文件夹复制出去，重装后放回原处，再点「导入备份」。
@Observable @MainActor final class LibraryBackup {
    enum Interval: String, CaseIterable, Identifiable {
        case off, daily, weekly
        var id: String { rawValue }
        var title: String {
            switch self {
            case .off: "关闭"
            case .daily: "每天"
            case .weekly: "每周"
            }
        }
        var seconds: TimeInterval? {
            switch self {
            case .off: nil
            case .daily: 24 * 3600
            case .weekly: 7 * 24 * 3600
            }
        }
    }

    static let fileName = "NeoDizzy-资料库.json"
    let folder: URL
    var fileURL: URL { folder.appending(path: Self.fileName) }

    var interval: Interval { didSet { defaults.set(interval.rawValue, forKey: Keys.interval) } }
    /// 备份里带上已注册平台的登录凭据，重装后恢复。
    var includesAccountLogin: Bool { didSet { defaults.set(includesAccountLogin, forKey: Keys.login) } }
    /// Compatibility with the previous preference name.
    var includesNeteaseLogin: Bool {
        get { includesAccountLogin }
        set { includesAccountLogin = newValue }
    }
    private(set) var lastBackup: Date?
    private(set) var lastError: String?
    private(set) var isRunning = false

    @ObservationIgnored private let defaults: UserDefaults
    private enum Keys {
        static let interval = "libraryBackup.interval"
        static let login = "libraryBackup.includesNeteaseLogin"
        static let last = "libraryBackup.lastBackup"
    }

    init(folder: URL = URL.documentsDirectory.appending(path: "Backup", directoryHint: .isDirectory), defaults: UserDefaults = .standard) {
        self.folder = folder
        self.defaults = defaults
        interval = defaults.string(forKey: Keys.interval).flatMap(Interval.init(rawValue:)) ?? .daily
        includesAccountLogin = defaults.object(forKey: Keys.login) as? Bool ?? true
        lastBackup = defaults.object(forKey: Keys.last) as? Date
        // 先建好文件夹，在「文件」App 里一眼就能找到放备份的位置。
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
    }

    /// 文件夹里有备份，但这次安装从没写过：多半是重装后刚放回来的旧备份，导入前不能被自动备份覆盖。
    var hasUnimportedBackup: Bool {
        lastBackup == nil && FileManager.default.fileExists(atPath: fileURL.path)
    }

    var isDue: Bool {
        guard let seconds = interval.seconds, !hasUnimportedBackup else { return false }
        return lastBackup.map { Date.now.timeIntervalSince($0) >= seconds } ?? true
    }

    func runIfDue(_ context: LibraryContext) async {
        guard isDue else { return }
        await backup(context)
    }

    @discardableResult
    func backup(_ context: LibraryContext) async -> Bool {
        guard !isRunning else { return false }
        isRunning = true
        defer { isRunning = false }
        do {
            var export = context.snapshot()
            // 恢复只需要在线集合本身；后台不联网读取每个歌单的歌曲。
            for index in export.collections.indices where !export.collections[index].songsComplete {
                export.collections[index].issue = export.collections[index].issue ?? "备份不读取在线歌曲列表。"
            }
            if includesAccountLogin { export.credentials = context.credentials() }
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            try export.data().write(to: fileURL, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
            lastError = nil
            markBackedUp()
            return true
        } catch {
            lastError = "备份失败：\(error.localizedDescription)"
            return false
        }
    }

    /// 导入后旧文件已经用过，之后的自动备份可以覆盖它。
    func markBackedUp() {
        lastBackup = .now
        defaults.set(lastBackup, forKey: Keys.last)
    }

    /// 找到 Backup 里的备份：优先固定文件名，否则用最新的一份 NeoDizzy 配置文件（例如被改了名）。
    func findBackup() throws -> (LibraryExport, URL) {
        if let data = try? Data(contentsOf: fileURL), let export = try? LibraryExport.decode(data) { return (export, fileURL) }
        let files = (try? FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: [.contentModificationDateKey])) ?? []
        let candidates = files.filter { $0.pathExtension.lowercased() == "json" }.sorted {
            let lhs = (try? $0.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast
            let rhs = (try? $1.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast
            return lhs > rhs
        }
        for url in candidates {
            if let data = try? Data(contentsOf: url), let export = try? LibraryExport.decode(data) { return (export, url) }
        }
        throw BackupError.notFound
    }

    enum BackupError: LocalizedError {
        case notFound
        var errorDescription: String? {
            "没有找到备份。请把备份文件放进「文件 › 我的 iPhone › NeoDizzy › Backup」，再点「导入备份」。"
        }
    }
}

#endif
