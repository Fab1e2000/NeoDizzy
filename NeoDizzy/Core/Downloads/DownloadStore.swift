import Foundation
import Observation

@Observable final class DownloadStore {
    private(set) var jobs: [DownloadJob]
    @ObservationIgnored private let library: OfflineLibraryStore
    @ObservationIgnored private let directory: URL
    @ObservationIgnored private let transport: DownloadTransport
    @ObservationIgnored private var providers: [String: any DownloadProvider] = [:]
    @ObservationIgnored private var operations: [UUID: Task<Void, Never>] = [:]
    @ObservationIgnored private var eventTask: Task<Void, Never>?
    @ObservationIgnored private var restored = false
    @ObservationIgnored private var progressByID: [UUID: DownloadProgress] = [:]

    init(library: OfflineLibraryStore, migrateLegacy: (Data) -> [DownloadJob]? = { _ in nil }) {
        self.library = library
        directory = URL.applicationSupportDirectory.appendingPathComponent("Downloads", isDirectory: true)
        if let data = try? Data(contentsOf: directory.appendingPathComponent("jobs.json")) {
            if let snapshot = try? JSONDecoder().decode(DownloadSnapshot.self, from: data), snapshot.version == 2 { jobs = snapshot.jobs }
            else { jobs = migrateLegacy(data) ?? [] }
        } else { jobs = [] }
        transport = DownloadTransport(directory: directory, identifier: BackgroundDownloadBridge.identifier)
    }

    func register(_ provider: any DownloadProvider) { providers[provider.id] = provider }
    func progress(for job: DownloadJob) -> DownloadProgress {
        if let progress = progressByID[job.id] { return progress }
        let progress = DownloadProgress(fraction: job.progress)
        progressByID[job.id] = progress
        return progress
    }

    func restore() async {
        guard !restored else { return }
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
            for await event in transport.events {
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
        let ids = Set(current.transfers.map(\.id))
        Task {
            for task in await transport.tasks() where task.taskDescription.flatMap(UUID.init(uuidString:)).map(ids.contains) == true { task.cancel() }
        }
        save(); pump()
    }

    func retry(_ job: DownloadJob) async {
        guard let current = jobs.first(where: { $0.id == job.id }), current.canRetry,
              operations[current.id] == nil,
              !jobs.contains(where: { $0.identity == current.identity && $0.isActive }) else { return }
        let replacement = DownloadJob(id: UUID(), providerID: current.providerID, requestData: current.requestData)
        cleanup(current)
        jobs.removeAll { $0.id == current.id }
        jobs.insert(replacement, at: 0)
        save(); pump()
    }

    private func pump() {
        guard restored else { return }
        var running = jobs.filter { $0.isActive && $0.state != .queued }.count
        for job in jobs.reversed() where job.isActive && operations[job.id] == nil {
            if job.state == .queued {
                guard running < 2 else { continue }
                running += 1
                update(job.id) { $0.state = .preparing }
            }
            guard !job.transfers.contains(where: { $0.state == .downloading }) else { continue }
            operations[job.id] = Task { [weak self] in await self?.advance(job.id) }
        }
        save()
    }

    private func advance(_ id: UUID) async {
        defer { operations[id] = nil; save(); pump() }
        guard let job = jobs.first(where: { $0.id == id }), let provider = providers[job.providerID] else {
            update(id) { $0.state = .failed; $0.failureMessage = "下载来源不可用" }; return
        }
        do {
            guard library.folderName != nil else { throw DownloadFailure.folderMissing }
            if job.transfers.isEmpty {
                let plan = try await provider.plan(job.requestData)
                try Task.checkCancellation()
                update(id) { $0.transfers = plan }
                save()
            }
            while let current = jobs.first(where: { $0.id == id }), current.isActive {
                try Task.checkCancellation()
                if let file = current.transfers.first(where: { $0.state == .downloaded }) {
                    let staging = directory.appendingPathComponent("\(file.id).contents")
                    defer { try? FileManager.default.removeItem(at: staging) }
                    do {
                        try? FileManager.default.removeItem(at: staging)
                        try FileManager.default.createDirectory(at: staging, withIntermediateDirectories: true)
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
                } else if let file = current.transfers.first(where: { $0.state == .queued }) {
                    do {
                        guard let source = try await provider.source(file) else {
                            updateTransfer(id, file.id) { $0.state = .completed }
                            continue
                        }
                        try Task.checkCancellation()
                        updateTransfer(id, file.id) { $0.metadata = source.metadata; $0.state = .downloading }
                        update(id) { $0.state = .downloading }
                        save()
                        transport.start(url: source.url, id: file.id, headers: source.headers)
                        return
                    } catch is CancellationError { throw CancellationError() }
                    catch { updateTransfer(id, file.id) { $0.state = .failed; $0.failure = DownloadTransport.message(for: error) } }
                } else {
                    try await provider.completed(current.requestData, transfers: jobs.first(where: { $0.id == id })?.transfers ?? current.transfers)
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
        catch { update(id) { $0.state = .failed; $0.failureMessage = DownloadTransport.message(for: error) } }
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
            let completed = job.transfers.filter { $0.state == .completed || $0.state == .failed }.count
            progress(for: job).fraction = expected > 0 ? (Double(completed) + min(1, Double(written) / Double(expected))) / Double(max(1, job.transfers.count)) : nil
        case .downloaded:
            updateTransfer(job.id, fileID) { if $0.state != .completed { $0.state = .downloaded; $0.failure = nil } }
            save(); pump()
        case .failed(_, let message):
            updateTransfer(job.id, fileID) { if $0.state == .downloading { $0.state = .failed; $0.failure = message } }
            save(); pump()
        case .finishedBackgroundEvents: break
        }
    }

    private func update(_ id: UUID, _ change: (inout DownloadJob) -> Void) {
        guard let index = jobs.firstIndex(where: { $0.id == id }) else { return }
        change(&jobs[index])
        if jobs[index].state != .downloading { progressByID[id] = nil }
    }
    private func updateTransfer(_ job: UUID, _ file: UUID, _ change: (inout DownloadTransfer) -> Void) {
        update(job) { value in
            guard let index = value.transfers.firstIndex(where: { $0.id == file }) else { return }
            change(&value.transfers[index])
        }
    }
    private func cleanup(_ job: DownloadJob) {
        for file in job.transfers {
            try? FileManager.default.removeItem(at: transport.archiveURL(file.id))
            try? FileManager.default.removeItem(at: directory.appendingPathComponent("\(file.id).contents"))
        }
    }
    private func save() {
        do {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            let data = try JSONEncoder().encode(DownloadSnapshot(version: 2, jobs: jobs))
            try data.write(to: directory.appendingPathComponent("jobs.json"), options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
            var location = directory
            var values = URLResourceValues(); values.isExcludedFromBackup = true
            try? location.setResourceValues(values)
        } catch { }
    }
}
