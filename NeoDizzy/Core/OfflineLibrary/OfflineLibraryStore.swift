import Foundation
import Observation

@Observable
@MainActor
final class OfflineLibraryStore {
    private(set) var albums: [OfflineAlbum] = []
    private(set) var folderName: String?
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

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    func restore() async {
        guard !hasRestored, folder == nil else { return }
        hasRestored = true
        guard let data = defaults.data(forKey: Self.bookmarkKey) else { return }
        folderGeneration += 1
        let generation = folderGeneration
        do {
            let prepared = try await worker.restore(data)
            guard generation == folderGeneration else { return }
            install(prepared)
            await scan()
        } catch {
            guard generation == folderGeneration else { return }
            issue = "无法恢复离线文件夹，请重新选择并授权。\(error.localizedDescription)"
        }
    }

    func selectFolder(_ url: URL) async throws {
        guard importsInFlight == 0 else { throw OfflineLibraryError.importing }
        folderSelectionsInFlight += 1
        defer { folderSelectionsInFlight -= 1 }
        folderGeneration += 1
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

    func scan() async {
        guard let folder else { return }
        scanGeneration += 1
        let scanID = scanGeneration
        let folderID = folderGeneration
        isScanning = true
        issue = nil
        do {
            let result = try await worker.scan(folder)
            guard scanID == scanGeneration, folderID == folderGeneration else { return }
            albums = result.albums
            issue = result.issues.isEmpty ? nil : result.issues.prefix(3).joined(separator: "\n")
        } catch is CancellationError {
            guard scanID == scanGeneration, folderID == folderGeneration else { return }
            // 扫描被取消时保留索引；尤其不能把已经提交的下载变成失败提示。
        } catch {
            guard scanID == scanGeneration, folderID == folderGeneration else { return }
            // 保留列表，播放前还会检查音频是否实际存在。
            issue = error.localizedDescription
        }
        if scanID == scanGeneration { isScanning = false }
    }

    func album(id: String) -> OfflineAlbum? {
        albums.first { $0.id == id }
    }

    func localFile(for track: Track) -> URL? {
        guard let folder, let album = album(id: track.discID),
              // 每次播放时再检查选中根目录的边界，防止扫描后目录被换成符号链接。
              album.directoryURL.standardizedFileURL.resolvingSymlinksInPath().path == folder.url.standardizedFileURL.resolvingSymlinksInPath().path ||
              (try? OfflinePaths.relativePath(of: album.directoryURL, inside: folder.url)) != nil else { return nil }
        return album.localFile(for: track)
    }

    func importAlbum(from extractedURL: URL, detail: DiscDetail) async throws {
        guard folderSelectionsInFlight == 0 else { throw OfflineLibraryError.folderChanged }
        guard let folder else { throw OfflineLibraryError.noFolder }
        guard album(id: detail.id) == nil else { throw OfflineLibraryError.existingAlbum }
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

    private func install(_ prepared: PreparedOfflineFolder) {
        // 原授权一直持有到这里；后台任务有自己的引用，可安全完成后再释放。
        folder = prepared.access
        folderName = prepared.access.url.lastPathComponent
        defaults.set(prepared.bookmark, forKey: Self.bookmarkKey)
        albums = []
        issue = nil
    }
}
