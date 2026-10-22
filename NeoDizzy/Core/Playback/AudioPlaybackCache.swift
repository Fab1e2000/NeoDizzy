import AVFoundation
import CryptoKit
import Foundation
import Observation

/// Only complete, validated responses enter the index. Signed URLs never reach disk.
@Observable final class AudioPlaybackCache {
    static let shared = AudioPlaybackCache()
    nonisolated struct Key: Codable, Hashable, Sendable {
        let trackID: String
        let scope: String
        let quality: String
        var name: String { AudioPlaybackCache.digest("\(scope)|\(trackID)|\(quality)") }
    }
    nonisolated struct Entry: Codable, Sendable {
        let key: Key
        let filename: String
        let actualQuality: String
        let bytes: Int64
        var used: Date
    }
    nonisolated static func digest(_ text: String) -> String {
        SHA256.hash(data: Data(text.utf8)).map { String(format: "%02x", $0) }.joined()
    }
    nonisolated static func mayContinue(listened: TimeInterval, duration: TimeInterval) -> Bool {
        listened.isFinite && duration.isFinite && duration > 0 && listened / duration > 0.9
    }
    private(set) var bytes: Int64 = 0
    private(set) var issue: String?
    /// 缓存里有哪些歌变了就加一，歌曲行靠它刷新「已缓存」标记。
    private(set) var revision = 0
    @ObservationIgnored private var cachedNames = Set<String>()
    let directory: URL
    let capacity: Int64
    @ObservationIgnored private var entries: [String: Entry] = [:]
    @ObservationIgnored private var jobs: [UUID: ProgressiveAudioLoader] = [:]
    @ObservationIgnored private var discarded = Set<UUID>()
    @ObservationIgnored private var completed = Set<UUID>()
    @ObservationIgnored private var detached: [UUID] = []
    @ObservationIgnored private var generation = 0
    @ObservationIgnored private var activeFiles = Set<URL>()

    init(directory: URL = URL.cachesDirectory.appendingPathComponent("ListeningAudio", isDirectory: true), capacity: Int64 = 2 * 1_024 * 1_024 * 1_024) {
        self.directory = directory; self.capacity = capacity
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        if let data = try? Data(contentsOf: directory.appendingPathComponent("index.json")),
           let saved = try? JSONDecoder().decode([String: Entry].self, from: data) {
            entries = saved.filter { _, entry in
                guard entry.filename == URL(fileURLWithPath: entry.filename).lastPathComponent else { return false }
                let size = try? directory.appendingPathComponent(entry.filename).resourceValues(forKeys: [.fileSizeKey]).fileSize
                return size.map(Int64.init) == entry.bytes && entry.bytes > 0
            }
        }
        let known = Set(entries.values.map(\.filename)).union(["index.json"])
        for url in (try? FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)) ?? [] where !known.contains(url.lastPathComponent) {
            try? FileManager.default.removeItem(at: url)
        }
        trim(); save()
    }
    func entry(for key: Key) -> Entry? {
        guard var entry = entries[key.name] else { return nil }
        let url = directory.appendingPathComponent(entry.filename)
        guard (try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize).map(Int64.init) == entry.bytes else {
            entries[key.name] = nil; save(); return nil
        }
        entry.used = .now; entries[key.name] = entry; save()
        return entry
    }
    /// 只读查询，供列表显示用：不更新最近使用时间，也不写盘。
    func cachedQuality(for key: Key) -> String? {
        _ = revision
        return entries[key.name]?.actualQuality
    }
    func file(for key: Key) -> URL? { entry(for: key).map { directory.appendingPathComponent($0.filename) } }
    func protect(_ url: URL?) {
        let previous = activeFiles
        activeFiles = Set([url].compactMap { $0 })
        for old in previous.subtracting(activeFiles) where old.deletingLastPathComponent().standardizedFileURL.path == directory.standardizedFileURL.path && !entries.values.contains(where: { $0.filename == old.lastPathComponent }) {
            try? FileManager.default.removeItem(at: old)
        }
    }
    func remove(_ key: Key) {
        if let entry = entries.removeValue(forKey: key.name) {
            let url = directory.appendingPathComponent(entry.filename)
            if !activeFiles.contains(url) { try? FileManager.default.removeItem(at: url) }
            save()
        }
    }

    func makeItem(url: URL, key: Key, actualQuality: String, configuration: URLSessionConfiguration = .ephemeral) -> (AVPlayerItem, UUID)? {
        let id = UUID(), generation = generation
        do {
            let loader = try ProgressiveAudioLoader(url: url, directory: directory, configuration: configuration) { [weak self] file, size, ext in
                Task { @MainActor [weak self] in
                    defer { if let file { try? FileManager.default.removeItem(at: file) } }
                    guard let self else { return }
                    if self.discarded.remove(id) == nil, self.generation == generation, let file {
                        do { try await self.commit(file, key: key, actualQuality: actualQuality, bytes: size, fileExtension: ext) }
                        catch { self.issue = "音频缓存保存失败，请检查可用空间。" }
                    }
                    guard self.jobs[id] != nil else { return }
                    self.completed.insert(id)
                    if self.detached.contains(id) { self.jobs[id] = nil; self.completed.remove(id) }
                    self.detached.removeAll { $0 == id }
                    // Active loaders remain alive to serve AVFoundation after the transfer finishes.
                }
            }
            jobs[id] = loader
            return (loader.makeItem(), id)
        } catch { issue = "无法创建音频缓存，已使用在线播放。"; return nil }
    }
    func discard(_ id: UUID?) {
        guard let id else { return }
        if completed.remove(id) == nil { discarded.insert(id) }
        detached.removeAll { $0 == id }
        jobs.removeValue(forKey: id)?.cancel()
    }
    func leave(_ id: UUID?, listened: TimeInterval, duration: TimeInterval) {
        guard let id, let job = jobs[id] else { return }
        if completed.remove(id) != nil { jobs[id] = nil; return }
        if Self.mayContinue(listened: listened, duration: duration) {
            detached.append(id)
            // Bound background work; the active song is never evicted here.
            while detached.count > 2 { let oldest = detached.removeFirst(); jobs.removeValue(forKey: oldest)?.cancel() }
        } else { jobs[id] = nil; job.cancel() }
    }
    /// 复制可能有几百 MB，放到后台执行；复制期间清理过缓存就丢弃这份。
    func commit(_ file: URL, key: Key, actualQuality: String, bytes: Int64, fileExtension: String) async throws {
        guard bytes > 0, bytes <= capacity else { throw PlaybackError.failed }
        let ext = AudioFileMatcher.extensions.contains(fileExtension.lowercased()) ? fileExtension.lowercased() : "audio"
        let filename = UUID().uuidString + "." + ext
        let target = directory.appendingPathComponent(filename)
        let generation = generation
        try await Task.detached(priority: .utility) {
            guard (try file.resourceValues(forKeys: [.fileSizeKey]).fileSize).map(Int64.init) == bytes else { throw PlaybackError.failed }
            try FileManager.default.copyItem(at: file, to: target)
        }.value
        guard self.generation == generation else { try? FileManager.default.removeItem(at: target); return }
        if let old = entries[key.name], !activeFiles.contains(directory.appendingPathComponent(old.filename)) {
            try? FileManager.default.removeItem(at: directory.appendingPathComponent(old.filename))
        }
        entries[key.name] = Entry(key: key, filename: filename, actualQuality: actualQuality, bytes: bytes, used: .now)
        trim(); save()
    }
    /// In-flight streams keep serving playback, but cannot repopulate a cleared cache.
    func clear() {
        generation += 1; issue = nil
        for id in detached { jobs.removeValue(forKey: id)?.cancel() }
        detached.removeAll()
        for (key, entry) in entries {
            let url = directory.appendingPathComponent(entry.filename)
            if activeFiles.contains(url) { entries[key] = nil; continue }
            do { try FileManager.default.removeItem(at: url); entries[key] = nil }
            catch { issue = "部分缓存未能删除，请稍后重试。" }
        }
        save()
    }
    private func trim() {
        var total = entries.values.reduce(Int64(0)) { $0 + $1.bytes }
        for entry in entries.values.sorted(by: { $0.used < $1.used }) where total > capacity {
            let url = directory.appendingPathComponent(entry.filename)
            guard !activeFiles.contains(url) else { continue }
            do { try FileManager.default.removeItem(at: url); entries[entry.key.name] = nil; total -= entry.bytes } catch { }
        }
    }
    private func save() {
        bytes = entries.values.reduce(0) { $0 + $1.bytes }
        let names = Set(entries.keys)
        if names != cachedNames { cachedNames = names; revision += 1 }
        if let data = try? JSONEncoder().encode(entries) { try? data.write(to: directory.appendingPathComponent("index.json"), options: .atomic) }
    }
}
