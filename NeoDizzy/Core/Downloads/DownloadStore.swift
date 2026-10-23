import Foundation
import Observation

@Observable final class DownloadStore {
    private(set) var persistenceError: String?
    @ObservationIgnored private let writeData: (Data, URL) throws -> Void
    static let concurrentDownloadRange = 1...6
    private static let concurrencyKey = "downloads.concurrentCount"
    var concurrentDownloadCount: Int {
        didSet {
            let bounded = min(6, max(1, concurrentDownloadCount))
            if bounded != concurrentDownloadCount { concurrentDownloadCount = bounded }
            defaults.set(bounded, forKey: Self.concurrencyKey)
            pump()
        }
    }
    @ObservationIgnored private let defaults: UserDefaults
    @ObservationIgnored private var sourceOperations: [UUID: Task<Void, Never>] = [:]
    private(set) var jobs: [DownloadJob]
    @ObservationIgnored private let library: OfflineLibraryStore
    @ObservationIgnored private let directory: URL
    @ObservationIgnored private let transport: DownloadTransport
    @ObservationIgnored private var providers: [String: any DownloadProvider] = [:]
    @ObservationIgnored private var operations: [UUID: Task<Void, Never>] = [:]
    @ObservationIgnored private var eventTask: Task<Void, Never>?
    @ObservationIgnored private var restored = false
    @ObservationIgnored private var transferProgressByID: [UUID: DownloadProgress] = [:]
    @ObservationIgnored private var progressByID: [UUID: DownloadProgress] = [:]

    init(library: OfflineLibraryStore, directory: URL? = nil, transportIdentifier: String = BackgroundDownloadBridge.identifier, defaults: UserDefaults = .standard, migrateLegacy: (Data) -> [DownloadJob]? = { _ in nil }, writeData: @escaping (Data, URL) throws -> Void = { try $0.write(to: $1, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication]) }) {
        self.writeData = writeData
        self.defaults = defaults
        let saved = defaults.object(forKey: Self.concurrencyKey) as? Int ?? 2
        concurrentDownloadCount = min(6, max(1, saved))
        self.library = library
        self.directory = directory ?? URL.applicationSupportDirectory.appendingPathComponent("Downloads", isDirectory: true)
        if let data = try? Data(contentsOf: self.directory.appendingPathComponent("jobs.json")) {
            if let snapshot = try? JSONDecoder().decode(DownloadSnapshot.self, from: data), snapshot.version == 2 { jobs = snapshot.jobs }
            else { jobs = migrateLegacy(data) ?? [] }
        } else { jobs = [] }
        transport = DownloadTransport(directory: self.directory, identifier: transportIdentifier)
    }

    func register(_ provider: any DownloadProvider) { providers[provider.id] = provider }
    /// Stop only this source. Queue records and committed library files remain available.
    /// Await writers before returning so callers can safely release the platform session.
    func unregister(_ providerID: String) async {
        providers[providerID] = nil
        let affected = jobs.filter { $0.providerID == providerID && $0.isActive }
        let ids = Set(affected.flatMap { $0.transfers.map(\.id) })
        let writers = affected.compactMap { operations[$0.id] }
        let sources = ids.compactMap { sourceOperations[$0] }
        for job in affected {
            update(job.id) { $0.state = .failed; $0.failureMessage = "下载来源不可用"; $0.progress = nil }
        }
        writers.forEach { $0.cancel() }
        sources.forEach { $0.cancel() }
        save()
        for task in await transport.tasks() where task.taskDescription.flatMap(UUID.init(uuidString:)).map(ids.contains) == true {
            task.cancel()
        }
        for writer in writers { await writer.value }
        for source in sources { await source.value }
        save(); pump()
    }

    func isAvailable(_ providerID: String) -> Bool { providers[providerID] != nil }

    func progress(for job: DownloadJob) -> DownloadProgress {
        if let progress = progressByID[job.id] { return progress }
        let progress = DownloadProgress(fraction: job.progress)
        progressByID[job.id] = progress
        return progress
    }

    func progress(for transfer: DownloadTransfer) -> DownloadProgress {
        if let progress = transferProgressByID[transfer.id] { return progress }
        let progress = DownloadProgress(fraction: nil)
        transferProgressByID[transfer.id] = progress
        return progress
    }

    func restore() async {
        guard !restored else { return }
        for provider in Array(providers.values) {
            for index in jobs.indices where jobs[index].providerID == provider.id {
                jobs[index] = provider.migrateRestoredJob(jobs[index])
                for transfer in jobs[index].transfers.indices where jobs[index].transfers[transfer].summary == nil {
                    jobs[index].transfers[transfer].summary = provider.summary(for: jobs[index].transfers[transfer])
                }
            }
            await provider.restore(jobs: jobs.filter { $0.providerID == provider.id })
        }
        // Unavailable sources must never resume their background network tasks.
        for index in jobs.indices where jobs[index].isActive && providers[jobs[index].providerID] == nil {
            jobs[index].state = .failed
            jobs[index].failureMessage = "下载来源不可用"
        }
        let tasks = await transport.tasks()
        let live = Set(tasks.compactMap { $0.taskDescription.flatMap(UUID.init(uuidString:)) })
        for index in jobs.indices where jobs[index].isActive {
            for file in jobs[index].transfers.indices {
                let transfer = jobs[index].transfers[file]
                guard transfer.state != .completed && transfer.state != .failed else { continue }
                if FileManager.default.fileExists(atPath: transport.archiveURL(transfer.id).path) {
                    jobs[index].transfers[file].state = .downloaded
                } else if live.contains(transfer.id) { jobs[index].transfers[file].state = .downloading }
                else { jobs[index].transfers[file].state = .queued }
            }
            jobs[index].state = .queued
        }
        let active = Set(jobs.filter(\.isActive).flatMap { $0.transfers.map(\.id) })
        for task in tasks {
            guard let id = task.taskDescription.flatMap(UUID.init(uuidString:)), active.contains(id) else { task.cancel(); continue }
            if task.state == .suspended { task.resume() }
        }
        restored = true
        eventTask = Task { [weak self] in
            for await event in self?.transport.events ?? AsyncStream { $0.finish() } {
                guard let self else { break }
                await self.handle(event)
            }
        }
        save(); pump()
    }

    func enqueue(providerID: String, request: DownloadRequest) async {
        guard let data = try? JSONEncoder().encode(request) else { return }
        let job = DownloadJob(id: UUID(), providerID: providerID, requestData: data)
        guard !jobs.contains(where: { $0.identity == job.identity && $0.isActive }) else { return }
        jobs.insert(job, at: 0)
        save(); pump()
    }

    func cancel(_ job: DownloadJob) {
        guard let current = jobs.first(where: { $0.id == job.id }), current.isActive else { return }
        update(job.id) { $0.state = .cancelled; $0.progress = nil }
        operations[job.id]?.cancel()
        for transfer in current.transfers { sourceOperations[transfer.id]?.cancel() }
        let ids = Set(current.transfers.map(\.id))
        Task {
            for task in await transport.tasks() where task.taskDescription.flatMap(UUID.init(uuidString:)).map(ids.contains) == true { task.cancel() }
        }
        save(); pump()
    }

    /// Removes queue history and unfinished temporary files; committed library files are untouched.
    func remove(_ job: DownloadJob) async {
        guard let current = jobs.first(where: { $0.id == job.id }) else { return }
        let operation = operations[current.id]
        operation?.cancel()
        let sources = current.transfers.compactMap { sourceOperations[$0.id] }
        sources.forEach { $0.cancel() }
        jobs.removeAll { $0.id == current.id }
        progressByID[current.id] = nil
        save()
        let ids = Set(current.transfers.map(\.id))
        for task in await transport.tasks() where task.taskDescription.flatMap(UUID.init(uuidString:)).map(ids.contains) == true {
            task.cancel()
        }
        // Let any file writer unwind before deleting its staging directory.
        await operation?.value
        for source in sources { await source.value }
        cleanup(current)
        pump()
    }

    func retry(_ job: DownloadJob) async {
        guard let current = jobs.first(where: { $0.id == job.id }), current.canRetry,
              operations[current.id] == nil,
              !current.transfers.contains(where: { sourceOperations[$0.id] != nil }),
              !jobs.contains(where: { $0.identity == current.identity && $0.isActive }) else { return }
        let replacement = DownloadJob(id: UUID(), providerID: current.providerID, requestData: current.requestData)
        cleanup(current)
        jobs.removeAll { $0.id == current.id }
        jobs.insert(replacement, at: 0)
        save(); pump()
    }

    private func pump() {
        guard restored, persistenceError == nil else { return }
        for job in jobs where job.isActive && providers[job.providerID] == nil {
            update(job.id) { $0.state = .failed; $0.failureMessage = "下载来源不可用" }
        }
        // Processing has its own bounded lane; network slots are per file, across all jobs.
        for job in jobs.reversed() where job.isActive && operations[job.id] == nil {
            guard operations.count < 2 else { break }
            let terminal = !job.transfers.isEmpty && job.transfers.allSatisfy { $0.state == .completed || $0.state == .failed }
            if job.transfers.isEmpty || job.transfers.contains(where: { $0.state == .downloaded }) || terminal {
                operations[job.id] = Task { [weak self] in await self?.advance(job.id) }
            }
        }
        var occupied = Set(jobs.filter(\.isActive).flatMap(\.transfers).filter { $0.state == .downloading }.map(\.id))
        occupied.formUnion(sourceOperations.keys)
        for job in jobs.reversed() where job.isActive {
            for file in job.transfers where file.state == .queued && sourceOperations[file.id] == nil {
                guard occupied.count < concurrentDownloadCount else { break }
                occupied.insert(file.id)
                sourceOperations[file.id] = Task { [weak self] in await self?.startTransfer(file, jobID: job.id) }
            }
        }
        for job in jobs where job.isActive && !job.transfers.isEmpty {
            let state: DownloadJob.State
            if job.transfers.contains(where: { $0.state == .processing }) { state = .importing }
            else if job.transfers.contains(where: { $0.state == .downloading }) { state = .downloading }
            else if job.transfers.contains(where: { sourceOperations[$0.id] != nil }) { state = .preparing }
            else if job.transfers.contains(where: { $0.state == .downloaded }) { state = .importing }
            else { continue }
            if job.state != state { update(job.id) { $0.state = state } }
        }
        save()
    }

    private func advance(_ id: UUID) async {
        defer { operations[id] = nil; save(); pump() }
        guard persistenceError == nil, let job = jobs.first(where: { $0.id == id }), job.isActive else { return }
        guard let provider = providers[job.providerID] else {
            update(id) { $0.state = .failed; $0.failureMessage = "下载来源不可用" }; return
        }
        do {
            try Task.checkCancellation()
            guard library.folderName != nil else { throw DownloadFailure.folderMissing }
            if job.transfers.isEmpty {
                update(id) { $0.state = .preparing }
                let plan = try await provider.plan(job.requestData).map { transfer in
                    var transfer = transfer
                    transfer.summary = transfer.summary ?? provider.summary(for: transfer)
                    return transfer
                }
                try Task.checkCancellation()
                guard !plan.isEmpty else { throw DownloadFailure.unavailable }
                update(id) { $0.transfers = plan }
                guard save() else { return }; pump()
            }
            while persistenceError == nil, let current = jobs.first(where: { $0.id == id }), current.isActive {
                try Task.checkCancellation()
                if let file = current.transfers.first(where: { $0.state == .downloaded }) {
                    let staging = directory.appendingPathComponent("\(file.id).contents")
                    defer { try? FileManager.default.removeItem(at: staging) }
                    do {
                        try? FileManager.default.removeItem(at: staging)
                        try FileManager.default.createDirectory(at: staging, withIntermediateDirectories: true)
                        updateTransfer(id, file.id) { $0.state = .processing }
                        update(id) { $0.state = .importing }
                        let prepared = try await provider.finalize(transport.archiveURL(file.id), metadata: file.metadata, staging: staging)
                        try Task.checkCancellation()
                        try await library.commit(staging: staging, folderName: prepared.folderName, provenance: prepared.provenance)
                        updateTransfer(id, file.id) { $0.state = .completed }
                        // 文件已落盘，但歌单等收尾操作完成前，任务仍保持可恢复状态。
                    } catch is CancellationError { throw CancellationError() }
                    catch { updateTransfer(id, file.id) { $0.state = .failed; $0.failure = DownloadTransport.message(for: error) } }
                    try? FileManager.default.removeItem(at: transport.archiveURL(file.id))
                    save()
                } else {
                    guard current.transfers.allSatisfy({ $0.state == .completed || $0.state == .failed }) else { return }
                    try await provider.completed(current.requestData, transfers: jobs.first(where: { $0.id == id })?.transfers ?? current.transfers)
                    try Task.checkCancellation()
                    let failures = current.transfers.filter { $0.state == .failed }
                    update(id) {
                        $0.state = !failures.isEmpty && failures.count == current.transfers.count ? .failed : .completed
                        $0.progress = 1
                        $0.failureMessage = failures.isEmpty ? nil : "\(failures.count) 首无法下载：\(failures.first?.failure ?? "请重试")"
                    }
                    return
                }
            }
        } catch is CancellationError { }
        catch {
            if jobs.first(where: { $0.id == id })?.isActive == true {
                update(id) { $0.state = .failed; $0.failureMessage = DownloadTransport.message(for: error) }
            }
        }
    }

    private func startTransfer(_ file: DownloadTransfer, jobID: UUID) async {
        defer { sourceOperations[file.id] = nil; save(); pump() }
        guard persistenceError == nil, let job = jobs.first(where: { $0.id == jobID }), job.isActive,
              let provider = providers[job.providerID] else { return }
        do {
            guard library.folderName != nil else { throw DownloadFailure.folderMissing }
            try Task.checkCancellation()
            guard let source = try await provider.source(file) else {
                try Task.checkCancellation()
                updateTransfer(jobID, file.id) { $0.state = .completed }
                return
            }
            try Task.checkCancellation()
            guard jobs.first(where: { $0.id == jobID })?.isActive == true else { return }
            updateTransfer(jobID, file.id) { $0.metadata = source.metadata; $0.state = .downloading }
            update(jobID) { $0.state = .downloading }
            guard save() else {
                updateTransfer(jobID, file.id) { $0.state = .queued }
                return
            }
            if source.url.isFileURL {
                // 「转为下载」复制缓存文件，大文件放到后台复制，避免卡住界面。
                let archive = transport.archiveURL(file.id), sourceURL = source.url
                try await Task.detached(priority: .utility) {
                    try FileManager.default.createDirectory(at: archive.deletingLastPathComponent(), withIntermediateDirectories: true)
                    try? FileManager.default.removeItem(at: archive)
                    try FileManager.default.copyItem(at: sourceURL, to: archive)
                }.value
                try Task.checkCancellation()
                updateTransfer(jobID, file.id) { $0.state = .downloaded }
            } else {
                transport.start(url: source.url, id: file.id, headers: source.headers)
            }
        } catch is CancellationError { }
        catch {
            updateTransfer(jobID, file.id) { $0.state = .failed; $0.failure = DownloadTransport.message(for: error) }
        }
    }

    private func handle(_ event: DownloadEvent) async {
        if case .finishedBackgroundEvents = event {
            for operation in Array(operations.values) { await operation.value }
            BackgroundDownloadBridge.finishEvents(); return
        }
        let fileID: UUID
        switch event {
        case .progress(let id, _, _), .downloaded(let id), .failed(let id, _): fileID = id
        case .finishedBackgroundEvents: return
        }
        guard let job = jobs.first(where: { $0.transfers.contains { $0.id == fileID } }), job.isActive else {
            if case .downloaded = event { try? FileManager.default.removeItem(at: transport.archiveURL(fileID)) }
            return
        }
        switch event {
        case .progress(_, let written, let expected):
            if let transfer = job.transfers.first(where: { $0.id == fileID }) {
                progress(for: transfer).update(received: written, expected: expected)
            }
            let fractions = job.transfers.map { transfer -> Double in
                switch transfer.state {
                case .completed, .failed, .downloaded, .processing: return 1
                case .downloading: return transferProgressByID[transfer.id]?.fraction ?? 0
                case .queued: return 0
                }
            }
            progress(for: job).fraction = fractions.reduce(0, +) / Double(max(1, job.transfers.count))
        case .downloaded:
            transferProgressByID[fileID]?.finish()
            updateTransfer(job.id, fileID) { if $0.state != .completed { $0.state = .downloaded; $0.failure = nil } }
            save(); pump()
        case .failed(_, let message):
            transferProgressByID[fileID]?.finish()
            updateTransfer(job.id, fileID) { if $0.state == .downloading { $0.state = .failed; $0.failure = message } }
            save(); pump()
        case .finishedBackgroundEvents: break
        }
    }

    private func update(_ id: UUID, _ change: (inout DownloadJob) -> Void) {
        guard let index = jobs.firstIndex(where: { $0.id == id }) else { return }
        change(&jobs[index])
        if !jobs[index].isActive { progressByID[id] = nil }
    }
    private func updateTransfer(_ job: UUID, _ file: UUID, _ change: (inout DownloadTransfer) -> Void) {
        update(job) { value in
            guard let index = value.transfers.firstIndex(where: { $0.id == file }) else { return }
            change(&value.transfers[index])
            if value.transfers[index].state != .downloading {
                transferProgressByID[file]?.finish()
                transferProgressByID[file] = nil
            }
        }
    }
    private func cleanup(_ job: DownloadJob) {
        for file in job.transfers {
            transferProgressByID[file.id] = nil
            try? FileManager.default.removeItem(at: transport.archiveURL(file.id))
            try? FileManager.default.removeItem(at: directory.appendingPathComponent("\(file.id).contents"))
        }
    }
    func retryPersistence() {
        if save() { pump() }
    }

    @discardableResult
    private func save() -> Bool {
        do {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            let data = try JSONEncoder().encode(DownloadSnapshot(version: 2, jobs: jobs))
            try writeData(data, directory.appendingPathComponent("jobs.json"))
            var location = directory
            var values = URLResourceValues(); values.isExcludedFromBackup = true
            try? location.setResourceValues(values)
            persistenceError = nil
            return true
        } catch {
            persistenceError = "下载队列尚未保存，新任务已暂停启动。请重试保存，成功前退出可能丢失队列更改。"
            return false
        }
    }
}
