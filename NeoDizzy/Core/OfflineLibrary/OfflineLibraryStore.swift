import Foundation
import Observation

@Observable
@MainActor
final class OfflineLibraryStore {
    private(set) var albums: [OfflineAlbum] = [] {
        didSet { contentRevision += 1 }
    }
    private(set) var localAlbums: [LocalAlbum] = [] {
        didSet { contentRevision += 1 }
    }
    private(set) var scanFolders: [LibraryFolder] = []
    @ObservationIgnored private var scanAccess: [UUID: OfflineFolderAccess] = [:]
    @ObservationIgnored private let scanner: LocalLibraryScanner
    @ObservationIgnored private var scanTask: Task<Void, Never>?
    private static let sourcesKey = "localLibrary.scanFolders.v1"
    private(set) var contentRevision = 0
    private(set) var folderName: String?
    private(set) var downloadFolderIssue: String?
    private(set) var isScanning = false
    private(set) var issue: String?

    @ObservationIgnored private let worker = OfflineLibraryWorker()
    @ObservationIgnored private let defaults: UserDefaults
    @ObservationIgnored private var folder: OfflineFolderAccess?
    @ObservationIgnored private var folderGeneration = 0
    @ObservationIgnored private var scanGeneration = 0
    @ObservationIgnored private var hasRestored = false
    @ObservationIgnored private var importsInFlight = 0
    @ObservationIgnored private var folderSelectionsInFlight = 0
    private static let bookmarkKey = "offlineLibrary.folderBookmark.v1"

    init(defaults: UserDefaults = .standard, scanner: LocalLibraryScanner = LocalLibraryScanner()) {
        self.defaults = defaults
        self.scanner = scanner
    }

    func restore() async {
        guard !hasRestored else { return }
        hasRestored = true
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
        var managed: [OfflineAlbum] = []
        var issues = downloadFolderIssue.map { [$0] } ?? []
        var managedTracks: [String: Track] = [:]
        var directories = Set<String>()
        do {
            for access in folders {
                try Task.checkCancellation()
                do {
                    let result = try await worker.scan(access)
                    issues += result.issues
                    for album in result.albums {
                        for entry in album.manifest.entries {
                            if let file = try? OfflinePaths.file(entry.relativePath, inside: album.directoryURL) {
                                managedTracks[LocalLibraryScanner.canonical(file)] = album.tracks.first { $0.id == entry.track.id }
                            }
                        }
                        if directories.insert(LocalLibraryScanner.canonical(album.directoryURL)).inserted {
                            managed.append(album)
                        }
                    }
                } catch is CancellationError { throw CancellationError() }
                catch {
                    issues.append("\(access.url.lastPathComponent)：\(error.localizedDescription)")
                    // Keep the previous records for inaccessible providers, not deleted files.
                    managed += albums.filter { contains($0.directoryURL, in: access) }
                }
            }
            let local = try await scanner.scan(folders, excluding: [], refreshMetadata: refreshMetadata, refreshPaths: refreshPaths, managedTracks: managedTracks)
            try Task.checkCancellation()
            guard scanID == scanGeneration, folderID == folderGeneration else { return }
            // Site lookup remains deterministic; duplicate directory aliases were removed above.
            var ids = Set<String>()
            albums = managed.filter { ids.insert($0.id).inserted }.sorted {
                $0.title.localizedStandardCompare($1.title) == .orderedAscending
            }
            localAlbums = local.albums
            issues += local.issues
            issue = issues.isEmpty ? nil : issues.prefix(5).joined(separator: "\n")
        } catch is CancellationError {
            // A superseded scan cannot replace the newer index.
        } catch {
            if scanID == scanGeneration, folderID == folderGeneration { issue = error.localizedDescription }
        }
    }

    func album(id: String) -> OfflineAlbum? {
        albums.first { $0.id == id }
    }

    func localAlbum(id: String) -> LocalAlbum? { localAlbums.first { $0.id == id || $0.previousIDs.contains(id) } }

    func availableTrackIDs(discID: String) async throws -> Set<String> {
        guard let album = album(id: discID), let access = allFolders.first(where: { contains(album.directoryURL, in: $0) }) else { return [] }
        return try await worker.availableTrackIDs(in: album, folder: access)
    }

    private func contains(_ url: URL, in access: OfflineFolderAccess) -> Bool {
        (try? access.url.resourceValues(forKeys: [.isSymbolicLinkKey]).isSymbolicLink) == false &&
        (LocalLibraryScanner.canonical(url) == LocalLibraryScanner.canonical(access.url) ||
         (try? OfflinePaths.relativePath(of: url, inside: access.url)) != nil)
    }

    func localAlbum(for track: Track) -> LocalAlbum? {
        localAlbums.first { $0.entries.contains { $0.track.id == track.id } }
    }

    private func localEntry(for track: Track) -> LocalAlbum.Entry? {
        // Folder boundaries can change while an older queue snapshot still carries its album ID.
        localAlbums.lazy.flatMap(\.entries).first { $0.track.id == track.id }
    }

    func access(for track: Track) -> OfflineFolderAccess? {
        let url: URL?
        if track.localSource != nil {
            url = localEntry(for: track)?.fileURL
        } else { url = album(id: track.discID)?.directoryURL }
        guard let url else { return nil }
        return allFolders.first { contains(url, in: $0) }
    }

    func localFile(for track: Track) -> URL? {
        guard let access = access(for: track) else { return nil }
        if track.localSource != nil {
            guard let entry = localEntry(for: track),
                  contains(entry.fileURL, in: access),
                  (try? entry.fileURL.resourceValues(forKeys: [.isRegularFileKey]).isRegularFile) == true else { return nil }
            return entry.fileURL
        }
        return album(id: track.discID)?.localFile(for: track)
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
        let siteTracks = albums.flatMap { album in
            album.tracks.compactMap { track -> Track? in
                guard let url = album.localFile(for: track),
                      var updated = byPath[LocalLibraryScanner.canonical(url)] else { return nil }
                updated.localSource = nil
                return updated
            }
        }
        return entries.map(\.track) + siteTracks
    }

    func importAlbum(from extractedURL: URL, detail: DiscDetail) async throws {
        guard folderSelectionsInFlight == 0 else { throw OfflineLibraryError.folderChanged }
        guard let folder else { throw OfflineLibraryError.noFolder }
        importsInFlight += 1
        defer { importsInFlight -= 1 }
        do {
            let committed = try await worker.importAlbum(from: extractedURL, detail: detail, into: folder)
            // 文件已提交时，取消只能停止后续扫描，不能丢弃实际存在的专辑。
            // 在下一次挂起之前发布，并使此前开始的扫描无法覆盖新记录。
            scanGeneration += 1
            isScanning = false
            issue = nil
            albums.removeAll { $0.id == committed.id }
            albums.append(committed)
            albums.sort { $0.title.localizedStandardCompare($1.title) == .orderedAscending }
            if !Task.isCancelled { await scan() }
        } catch {
            issue = error.localizedDescription
            throw error
        }
    }

    func importGift(from extractedURL: URL, detail: DiscDetail) async throws {
        guard folderSelectionsInFlight == 0 else { throw OfflineLibraryError.folderChanged }
        guard let folder else { throw OfflineLibraryError.noFolder }
        importsInFlight += 1
        defer { importsInFlight -= 1 }
        try await worker.importGift(from: extractedURL, detail: detail,
                                    albumDirectory: album(id: detail.id).flatMap { contains($0.directoryURL, in: folder) ? $0.directoryURL : nil }, into: folder)
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
