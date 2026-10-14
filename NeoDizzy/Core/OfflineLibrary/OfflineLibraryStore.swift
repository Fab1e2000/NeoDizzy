import Foundation
import Observation

@Observable
@MainActor
final class OfflineLibraryStore {
    private(set) var collections: [LibraryCollection] = [] {
        didSet { contentRevision += 1; rebuildSourceIndex() }
    }
    private(set) var localAlbums: [LocalAlbum] = [] {
        didSet { contentRevision += 1 }
    }
    private(set) var scanFolders: [LibraryFolder] = []
    @ObservationIgnored private var scanAccess: [UUID: OfflineFolderAccess] = [:]
    @ObservationIgnored private let scanner: LocalLibraryScanner
    @ObservationIgnored private var scanTask: Task<Void, Never>?
    private static let snapshotKey = "localLibrary.indexSnapshot.v2"
    private struct IndexSnapshot: Codable {
        let downloadBookmark: Data?
        let sources: Data?
        let collections: [LibraryCollection]
        let localAlbums: [LocalAlbum]
    }
    private static let sourcesKey = "localLibrary.scanFolders.v1"
    private(set) var contentRevision = 0
    private(set) var folderName: String?
    private(set) var downloadFolderIssue: String?
    private(set) var isScanning = false
    private(set) var issue: String?
    /// 最近一次导入的结果，显示在本地库和音乐文件夹页。
    private(set) var importMessage: String?
    private var importsRunning = 0
    var isImporting: Bool { importsRunning > 0 }

    /// iOS 的音乐库固定在 App 自己的文件夹（「文件 › 我的 iPhone › NeoDizzy」），读写都不需要用户授权。
    /// 为 nil 时（Mac、测试）沿用用户选择并授权的文件夹。
    @ObservationIgnored let libraryRoot: URL?

    @ObservationIgnored private let worker = OfflineLibraryWorker()
    @ObservationIgnored private let defaults: UserDefaults
    @ObservationIgnored private var folder: OfflineFolderAccess?
    @ObservationIgnored private var folderGeneration = 0
    @ObservationIgnored private var scanGeneration = 0
    @ObservationIgnored private var hasRestored = false
    @ObservationIgnored private var importsInFlight = 0
    @ObservationIgnored private var folderSelectionsInFlight = 0
    private static let bookmarkKey = "offlineLibrary.folderBookmark.v1"

    init(defaults: UserDefaults = .standard, scanner: LocalLibraryScanner = LocalLibraryScanner(), libraryRoot: URL? = nil) {
        self.defaults = defaults
        self.scanner = scanner
        self.libraryRoot = libraryRoot
        if let libraryRoot {
            // 旧版本记住的外部文件夹不再使用；那里的音乐需要用户自己移进 App 文件夹。
            defaults.removeObject(forKey: Self.bookmarkKey)
            defaults.removeObject(forKey: Self.sourcesKey)
            try? FileManager.default.createDirectory(at: libraryRoot, withIntermediateDirectories: true)
            folder = OfflineFolderAccess(url: libraryRoot)
            folderName = "NeoDizzy"
        }
        // Seed UI before the first frame. Bookmarks are still restored before file access.
        if let data = defaults.data(forKey: Self.snapshotKey),
           let snapshot = try? JSONDecoder().decode(IndexSnapshot.self, from: data),
           snapshot.downloadBookmark == defaults.data(forKey: Self.bookmarkKey),
           snapshot.sources == defaults.data(forKey: Self.sourcesKey) {
            collections = snapshot.collections
            localAlbums = snapshot.localAlbums
        }
    }

    var downloadRoot: URL? { folder?.url }

    func restore() async {
        guard !hasRestored else { return }
        hasRestored = true
        if libraryRoot != nil {
            await scan(refreshMetadata: false)
            return
        }
        folderGeneration += 1
        let generation = folderGeneration
        if let data = defaults.data(forKey: Self.sourcesKey) {
            scanFolders = (try? JSONDecoder().decode([LibraryFolder].self, from: data)) ?? []
        }
        if let data = defaults.data(forKey: Self.bookmarkKey) {
            do {
                let prepared = try await worker.restore(data)
                guard generation == folderGeneration else { return }
                install(prepared)
            } catch {
                guard generation == folderGeneration else { return }
                downloadFolderIssue = "无法恢复下载目录，请重新选择并授权。\(error.localizedDescription)"
            }
        }
        for source in scanFolders {
            do {
                let prepared = try await worker.restore(source.bookmark)
                guard generation == folderGeneration else { return }
                scanAccess[source.id] = prepared.access
                if let index = scanFolders.firstIndex(where: { $0.id == source.id }) {
                    scanFolders[index].bookmark = prepared.bookmark
                    scanFolders[index].issue = nil
                }
            } catch {
                guard generation == folderGeneration else { return }
                if let index = scanFolders.firstIndex(where: { $0.id == source.id }) {
                    scanFolders[index].issue = "无法访问，请重新授权。"
                }
            }
        }
        saveSources()
        await scan(refreshMetadata: false)
    }

    func addScanFolder(_ url: URL, replacing id: UUID? = nil) async throws {
        let generation = folderGeneration
        let prepared = try await worker.prepare(url)
        guard generation == folderGeneration else { throw OfflineLibraryError.folderChanged }
        let canonical = LocalLibraryScanner.canonical(prepared.access.url)
        if let folder, LocalLibraryScanner.canonical(folder.url) == canonical { return }
        if scanAccess.contains(where: { $0.key != id && LocalLibraryScanner.canonical($0.value.url) == canonical }) { return }
        let source = LibraryFolder(id: id ?? UUID(), name: url.lastPathComponent, bookmark: prepared.bookmark)
        scanFolders.removeAll { $0.id == source.id }
        scanFolders.append(source)
        scanAccess[source.id] = prepared.access
        folderGeneration += 1
        saveSources()
        await scan()
    }

    func removeScanFolder(_ id: UUID) async {
        scanFolders.removeAll { $0.id == id }
        scanAccess[id] = nil
        folderGeneration += 1
        saveSources()
        await scan()
    }

    /// 把选中或分享来的文件放进 App 的音乐文件夹，然后刷新本地库。
    func importItems(_ urls: [URL]) async {
        guard let libraryRoot, !urls.isEmpty else { return }
        importsRunning += 1
        defer { importsRunning -= 1 }
        importMessage = nil
        do {
            let summary = try await LibraryImporter.importItems(urls, into: libraryRoot)
            importMessage = summary.message
            if summary.tracks > 0 { await scan(refreshMetadata: false) }
        } catch is CancellationError {
        } catch {
            importMessage = "导入失败：\(error.localizedDescription)"
        }
    }

    private func saveSources() {
        if let data = try? JSONEncoder().encode(scanFolders) { defaults.set(data, forKey: Self.sourcesKey) }
    }

    private var allFolders: [OfflineFolderAccess] {
        (folder.map { [$0] } ?? []) + scanFolders.compactMap { scanAccess[$0.id] }
    }

    func selectFolder(_ url: URL) async throws {
        guard importsInFlight == 0 else { throw OfflineLibraryError.importing }
        folderSelectionsInFlight += 1
        defer { folderSelectionsInFlight -= 1 }
        folderGeneration += 1
        scanTask?.cancel()
        scanGeneration += 1
        isScanning = false
        let generation = folderGeneration
        do {
            let prepared = try await worker.prepare(url)
            guard generation == folderGeneration else { throw OfflineLibraryError.folderChanged }
            install(prepared)
            hasRestored = true
            await scan()
        } catch {
            if generation == folderGeneration { issue = error.localizedDescription }
            throw error
        }
    }

    func scan(refreshMetadata: Bool = true, refreshPaths: Set<String> = []) async {
        scanTask?.cancel()
        scanGeneration += 1
        let scanID = scanGeneration
        let folderID = folderGeneration
        let folders = allFolders
        isScanning = true
        let task = Task { await performScan(folders, scanID: scanID, folderID: folderID, refreshMetadata: refreshMetadata, refreshPaths: refreshPaths) }
        scanTask = task
        await withTaskCancellationHandler { await task.value } onCancel: { task.cancel() }
    }

    private func performScan(_ folders: [OfflineFolderAccess], scanID: Int, folderID: Int, refreshMetadata: Bool, refreshPaths: Set<String>) async {
        defer { if scanID == scanGeneration { isScanning = false } }
        var managed: [LibraryCollection] = []
        var issues = downloadFolderIssue.map { [$0] } ?? []
        var directories = Set<String>()
        do {
            for access in folders {
                try Task.checkCancellation()
                do {
                    let result = try await worker.scan(access)
                    issues += result.issues
                    for album in result.albums {
                        if directories.insert(LocalLibraryScanner.canonical(album.directoryURL)).inserted {
                            managed.append(album)
                        }
                    }
                } catch is CancellationError { throw CancellationError() }
                catch {
                    issues.append("\(access.url.lastPathComponent)：\(error.localizedDescription)")
                    // Keep the previous records for inaccessible providers, not deleted files.
                    managed += collections.filter { contains($0.directoryURL, in: access) }
                }
            }
            let sourceIndex = makeSourceIndex(managed)
            let managedTracks = Dictionary(sourceIndex.values.map { (LocalLibraryScanner.canonical($0.fileURL), $0.track) },
                                           uniquingKeysWith: { first, _ in first })
            let local = try await scanner.scan(folders, excluding: [], refreshMetadata: refreshMetadata, refreshPaths: refreshPaths, managedTracks: managedTracks)
            try Task.checkCancellation()
            guard scanID == scanGeneration, folderID == folderGeneration else { return }
            // Site lookup remains deterministic; duplicate directory aliases were removed above.
            var ids = Set<LibrarySource>()
            collections = managed.filter { ids.insert($0.manifest.source).inserted }.sorted {
                $0.title.localizedStandardCompare($1.title) == .orderedAscending
            }
            localAlbums = local.albums
            saveIndexSnapshot()
            issues += local.issues
            issue = issues.isEmpty ? nil : issues.prefix(5).joined(separator: "\n")
        } catch is CancellationError {
            // A superseded scan cannot replace the newer index.
        } catch {
            if scanID == scanGeneration, folderID == folderGeneration { issue = error.localizedDescription }
        }
    }

    private func saveIndexSnapshot() {
        let snapshot = IndexSnapshot(downloadBookmark: defaults.data(forKey: Self.bookmarkKey),
                                     sources: defaults.data(forKey: Self.sourcesKey),
                                     collections: collections, localAlbums: localAlbums)
        if let data = try? JSONEncoder().encode(snapshot) {
            defaults.set(data, forKey: Self.snapshotKey)
        }
    }

    func localAlbum(id: String) -> LocalAlbum? { localAlbums.first { $0.id == id || $0.previousIDs.contains(id) } }

    private func contains(_ url: URL, in access: OfflineFolderAccess) -> Bool {
        (try? access.url.resourceValues(forKeys: [.isSymbolicLinkKey]).isSymbolicLink) == false &&
        (LocalLibraryScanner.canonical(url) == LocalLibraryScanner.canonical(access.url) ||
         (try? OfflinePaths.relativePath(of: url, inside: access.url)) != nil)
    }

    func localAlbum(for track: Track) -> LocalAlbum? {
        guard track.remoteSource == nil else { return nil }
        return localAlbums.first { $0.entries.contains { $0.track.id == track.id } }
    }

    private func localEntry(for track: Track) -> LocalAlbum.Entry? {
        // Folder boundaries can change while an older queue snapshot still carries its album ID.
        localAlbums.lazy.flatMap(\.entries).first { $0.track.id == track.id }
    }

    private struct SourceFile {
        let fileURL: URL
        let directoryURL: URL
        let track: Track
    }
    @ObservationIgnored private var sourceFiles: [RemoteTrackKey: SourceFile] = [:]

    func collection(provider: String, kind: String, id: String) -> LibraryCollection? {
        collections.first { $0.manifest.source == LibrarySource(provider: provider, kind: kind, id: id) }
    }

    func localTrackKeys(provider: String, collectionID: String) async throws -> Set<RemoteTrackKey> {
        var keys = Set<RemoteTrackKey>()
        for record in collections where record.manifest.source.provider == provider && record.manifest.source.id == collectionID {
            guard let access = allFolders.first(where: { contains(record.directoryURL, in: $0) }) else { continue }
            let available = try await worker.availableTrackKeys(in: record, folder: access)
            keys.formUnion(available)
        }
        return keys
    }

    private func rebuildSourceIndex() { sourceFiles = makeSourceIndex(collections) }

    private func makeSourceIndex(_ records: [LibraryCollection]) -> [RemoteTrackKey: SourceFile] {
        var index: [RemoteTrackKey: SourceFile] = [:]
        for record in records {
            for (entry, track) in zip(record.manifest.entries, record.tracks) {
                let key = RemoteTrackKey(provider: record.manifest.source.provider, itemID: entry.itemID)
                guard index[key] == nil, let file = record.localFile(for: entry.track) else { continue }
                index[key] = SourceFile(fileURL: file, directoryURL: record.directoryURL, track: track)
            }
        }
        return index
    }

    func access(for track: Track) -> OfflineFolderAccess? {
        let url: URL?
        if track.localSource != nil { url = localEntry(for: track)?.fileURL }
        else { url = track.remoteKey.flatMap { sourceFiles[$0]?.directoryURL } }
        guard let url else { return nil }
        return allFolders.first { contains(url, in: $0) }
    }

    func localFile(for track: Track) -> URL? {
        guard let access = access(for: track) else { return nil }
        let url: URL?
        if track.localSource != nil { url = localEntry(for: track)?.fileURL }
        else { url = track.remoteKey.flatMap { sourceFiles[$0]?.fileURL } }
        guard var url, contains(url, in: access) else { return nil }
        url.removeAllCachedResourceValues()
        guard (try? url.resourceValues(forKeys: [.isRegularFileKey, .isSymbolicLinkKey])).map({ $0.isRegularFile == true && $0.isSymbolicLink != true }) == true else { return nil }
        return url
    }

    func saveTags(_ draft: AudioTagDocument, snapshot: AudioTagSnapshot, url: URL, access: OfflineFolderAccess) async throws {
        guard folderSelectionsInFlight == 0 else { throw OfflineLibraryError.folderChanged }
        importsInFlight += 1
        defer { importsInFlight -= 1 }
        try await AudioTagEditor.shared.save(draft, snapshot: snapshot, url: url, access: access)
    }

    func refreshAfterTagEdit(_ url: URL) async throws -> [Track] {
        try await refreshAfterTagEdits([url])
    }

    func refreshAfterTagEdits(_ urls: [URL]) async throws -> [Track] {
        let revision = contentRevision
        let paths = Set(urls.map(LocalLibraryScanner.canonical))
        await scan(refreshMetadata: false, refreshPaths: paths)
        let indexedPaths = Set(localAlbums.flatMap(\.entries).map { LocalLibraryScanner.canonical($0.fileURL) })
        guard contentRevision > revision,
              paths.isSubset(of: indexedPaths) else {
            throw AudioTagError.message(issue ?? "索引刷新未完成，请重试刷新。")
        }
        let entries = localAlbums.flatMap(\.entries)
        let byPath = Dictionary(entries.map { (LocalLibraryScanner.canonical($0.fileURL), $0.track) },
                                uniquingKeysWith: { first, _ in first })
        // Queues opened from a site page still use site IDs. Refresh those from
        // the exact download selected by localFile(for:), never another copy.
        let siteTracks = collections.flatMap { album in
            album.tracks.compactMap { track -> Track? in
                guard let url = album.localFile(for: track),
                      let updated = byPath[LocalLibraryScanner.canonical(url)] else { return nil }
                return Track(discID: track.discID, number: track.number, title: updated.title,
                             artists: updated.artists, albumTitle: updated.albumTitle, coverURL: updated.coverURL,
                             duration: updated.duration, remoteSource: track.remoteSource)
            }
        }
        return entries.map(\.track) + siteTracks
    }

    /// 站点适配层准备提交内容；切换目录和过期扫描的保护集中在这里。
    func performImport(_ operation: (OfflineLibraryWorker, OfflineFolderAccess) async throws -> LibraryCollection?) async throws {
        guard folderSelectionsInFlight == 0 else { throw OfflineLibraryError.folderChanged }
        guard let folder else { throw OfflineLibraryError.noFolder }
        importsInFlight += 1
        defer { importsInFlight -= 1 }
        do {
            guard let committed = try await operation(worker, folder) else { return }
            scanGeneration += 1
            isScanning = false
            issue = nil
            collections.removeAll { $0.manifest.source == committed.manifest.source }
            collections.append(committed)
            collections.sort { $0.title.localizedStandardCompare($1.title) == .orderedAscending }
            if !Task.isCancelled { await scan() }
        } catch {
            issue = error.localizedDescription
            throw error
        }
    }

    private func install(_ prepared: PreparedOfflineFolder) {
        // 原授权一直持有到这里；后台任务有自己的引用，可安全完成后再释放。
        if let old = folder, LocalLibraryScanner.canonical(old.url) != LocalLibraryScanner.canonical(prepared.access.url),
           let bookmark = defaults.data(forKey: Self.bookmarkKey),
           !scanAccess.values.contains(where: { LocalLibraryScanner.canonical($0.url) == LocalLibraryScanner.canonical(old.url) }) {
            let source = LibraryFolder(id: UUID(), name: old.url.lastPathComponent, bookmark: bookmark)
            scanFolders.append(source)
            scanAccess[source.id] = old
        }
        let duplicates = scanAccess.filter { LocalLibraryScanner.canonical($0.value.url) == LocalLibraryScanner.canonical(prepared.access.url) }.map(\.key)
        for id in duplicates { scanAccess[id] = nil; scanFolders.removeAll { $0.id == id } }
        saveSources()
        downloadFolderIssue = nil
        folder = prepared.access
        folderName = prepared.access.url.lastPathComponent
        defaults.set(prepared.bookmark, forKey: Self.bookmarkKey)
        issue = nil
    }
}
