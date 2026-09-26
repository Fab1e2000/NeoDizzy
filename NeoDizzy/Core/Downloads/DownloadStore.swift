import Foundation

@Observable
final class DownloadStore {
    private(set) var jobs: [DownloadJob]
    @ObservationIgnored private let library: OfflineLibraryStore
    @ObservationIgnored private let directory: URL
    @ObservationIgnored private let transport: DownloadTransport
    @ObservationIgnored private var operations: [UUID: Task<Void, Never>] = [:]
    @ObservationIgnored private var eventTask: Task<Void, Never>?
    @ObservationIgnored private var restored = false

    init(library: OfflineLibraryStore) {
        self.library = library
        directory = URL.applicationSupportDirectory.appendingPathComponent("Downloads", isDirectory: true)
        let persistence = directory.appendingPathComponent("jobs.json")
        jobs = (try? Data(contentsOf: persistence)).flatMap { try? JSONDecoder().decode([DownloadJob].self, from: $0) } ?? []
        transport = DownloadTransport(directory: directory, identifier: BackgroundDownloadBridge.identifier)
    }

    /// Reconnects OS-owned transfers. Completed temporary files are already moved by the delegate,
    /// and buffered delegate events are consumed only after the library has restored its bookmark.
    func restore() async {
        guard !restored else { return }
        restored = true
        // The process may have been terminated after the atomic library commit but before job persistence.
        for job in jobs where library.album(id: job.discID) != nil {
            update(job.id) { $0.state = .completed; $0.progress = 1; $0.failureMessage = nil }
        }
        cleanupInactiveFiles()
        let tasks = await transport.tasks()
        var liveIDs = Set<UUID>()
        for task in tasks {
            guard let id = task.taskDescription.flatMap(UUID.init(uuidString:)),
                  let job = jobs.first(where: { $0.id == id }), job.isActive else { task.cancel(); continue }
            liveIDs.insert(id)
            update(id) { $0.state = .downloading }
            if task.state == .suspended { task.resume() }
        }
        for job in jobs where job.isActive && job.state != .queued {
            if FileManager.default.fileExists(atPath: transport.archiveURL(job.id).path) {
                processArchive(job.id)
            } else if !liveIDs.contains(job.id), operations[job.id] == nil {
                fail(job.id, DownloadFailure.interrupted.localizedDescription)
            }
        }
        let events = transport.events
        eventTask = Task { [weak self] in
            for await event in events {
                guard let self else { break }
                await self.handle(event)
            }
        }
        save()
        pump()
    }

    /// Inserts immediately so the sheet can dismiss while fresh authorization is fetched.
    func enqueue(detail: DiscDetail, option: DownloadOption) async {
        guard library.album(id: detail.id) == nil,
              !jobs.contains(where: { $0.discID == detail.id && $0.isActive }) else { return }
        let job = DownloadJob(id: UUID(), album: DownloadAlbum(detail), format: option.format)
        jobs.insert(job, at: 0)
        save()
        pump()
    }

    func cancel(_ job: DownloadJob) {
        guard jobs.first(where: { $0.id == job.id })?.isActive == true else { return }
        update(job.id) { $0.state = .cancelled; $0.progress = nil }
        operations[job.id]?.cancel()
        operations[job.id] = nil
        Task {
            for task in await transport.tasks() where task.taskDescription == job.id.uuidString { task.cancel() }
        }
        // Keep extraction cleanup within its operation to avoid racing an open file handle.
        if !FileManager.default.fileExists(atPath: extractionURL(job.id).path) {
            try? FileManager.default.removeItem(at: transport.archiveURL(job.id))
        }
        save()
        pump()
    }

    func retry(_ job: DownloadJob) async {
        guard let current = jobs.first(where: { $0.id == job.id }), current.canRetry,
              library.album(id: current.discID) == nil,
              !jobs.contains(where: { $0.discID == current.discID && $0.isActive }) else { return }
        try? FileManager.default.removeItem(at: transport.archiveURL(job.id))
        try? FileManager.default.removeItem(at: extractionURL(job.id))
        // A new ID prevents a late cancellation/error from an old URLSession task affecting the retry.
        let replacement = DownloadJob(id: UUID(), album: current.album, format: current.format)
        jobs.removeAll { $0.id == job.id }
        jobs.insert(replacement, at: 0)
        save()
        pump()
    }

    /// Bound total in-flight work, including extraction/import, to two albums.
    private func pump() {
        guard restored else { return }
        let running = jobs.filter { $0.isActive && $0.state != .queued }.count
        for job in jobs.reversed().filter({ $0.state == .queued }).prefix(max(0, 2 - running)) {
            update(job.id) { $0.state = .preparing }
            prepare(job.id)
        }
        save()
    }

    private func prepare(_ id: UUID) {
        operations[id] = Task { [weak self] in
            guard let self, let job = jobs.first(where: { $0.id == id }) else { return }
            defer { operations[id] = nil; pump() }
            do {
                guard library.folderName != nil else { throw DownloadFailure.folderMissing }
                let options = try await DizzyPages.shared.downloadOptions(discID: job.discID)
                guard let fresh = options.first(where: { $0.format == job.format }) else { throw DownloadFailure.unavailable }
                let url = try await DownloadLinkResolver.resolve(fresh.url, credentials: DizzyHTTPClient.shared.credentials)
                try Task.checkCancellation()
                guard jobs.first(where: { $0.id == id })?.state == .preparing else { return }
                update(id) { $0.state = .downloading }
                save()
                transport.start(url: url, id: id)
            } catch is CancellationError { }
            catch { fail(id, DownloadTransport.message(for: error)) }
        }
    }

    private func handle(_ event: DownloadEvent) async {
        switch event {
        case .progress(let id, let written, let expected):
            guard jobs.first(where: { $0.id == id })?.state == .downloading else { return }
            update(id) { $0.progress = expected > 0 ? min(1, max(0, Double(written) / Double(expected))) : nil }
        case .downloaded(let id):
            // A completed task can disappear from allTasks just before its final delegate callback.
            if let job = jobs.first(where: { $0.id == id }), job.state == .failed,
               job.failureMessage == DownloadFailure.interrupted.localizedDescription {
                update(id) { $0.state = .extracting; $0.failureMessage = nil }
            }
            guard jobs.first(where: { $0.id == id })?.isActive == true else {
                try? FileManager.default.removeItem(at: transport.archiveURL(id)); return
            }
            processArchive(id)
        case .failed(let id, let message): fail(id, message)
        case .finishedBackgroundEvents:
            // Processing is part of this background delivery; release iOS's completion only after it finishes.
            let pending = Array(operations.values)
            for operation in pending { await operation.value }
            BackgroundDownloadBridge.finishEvents()
        }
    }

    private func processArchive(_ id: UUID) {
        guard operations[id] == nil, let job = jobs.first(where: { $0.id == id }), job.isActive else { return }
        update(id) { $0.state = .extracting; $0.progress = nil }
        save()
        operations[id] = Task { [weak self] in
            guard let self else { return }
            let zip = transport.archiveURL(id)
            let extraction = extractionURL(id)
            defer {
                operations[id] = nil
                try? FileManager.default.removeItem(at: extraction)
                try? FileManager.default.removeItem(at: zip)
                pump()
            }
            do {
                try? FileManager.default.removeItem(at: extraction)
                try await SafeZipExtractor.extract(zip, into: extraction, expectedTracks: job.album.tracks)
                try Task.checkCancellation()
                guard jobs.first(where: { $0.id == id })?.isActive == true else { return }
                update(id) { $0.state = .importing }
                save()
                try await library.importAlbum(from: extraction, detail: job.album.detail)
                // A successful atomic import wins a late cancellation; the album really exists.
                update(id) { $0.state = .completed; $0.progress = 1 }
                save()
            } catch is CancellationError { }
            catch { fail(id, DownloadTransport.message(for: error)) }
        }
    }

    private func cleanupInactiveFiles() {
        let active = Set(jobs.filter(\.isActive).map(\.id))
        let files = (try? FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)) ?? []
        for file in files where ["zip", "contents"].contains(file.pathExtension) {
            guard let id = UUID(uuidString: file.deletingPathExtension().lastPathComponent), !active.contains(id) else { continue }
            try? FileManager.default.removeItem(at: file)
        }
    }

    private func extractionURL(_ id: UUID) -> URL { directory.appendingPathComponent(id.uuidString + ".contents", isDirectory: true) }

    private func update(_ id: UUID, _ change: (inout DownloadJob) -> Void) {
        guard let index = jobs.firstIndex(where: { $0.id == id }) else { return }
        change(&jobs[index])
    }

    private func fail(_ id: UUID, _ message: String) {
        guard jobs.first(where: { $0.id == id })?.isActive == true else { return }
        update(id) { $0.state = .failed; $0.failureMessage = message; $0.progress = nil }
        if operations[id] == nil { try? FileManager.default.removeItem(at: transport.archiveURL(id)) }
        save()
        pump()
    }

    private func save() {
        do {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            let data = try JSONEncoder().encode(jobs)
            try data.write(to: directory.appendingPathComponent("jobs.json"), options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
            var location = directory
            var values = URLResourceValues()
            values.isExcludedFromBackup = true
            try? location.setResourceValues(values)
        } catch { /* Keep usable in-memory state; an interrupted unsaved job is reconciled against URLSession on restore. */ }
    }
}
