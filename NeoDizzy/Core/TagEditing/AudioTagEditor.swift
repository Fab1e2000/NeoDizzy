import Foundation
import CryptoKit

/// Complete content digest plus file identity detects in-place edits and replacements.
nonisolated struct AudioTagFileStamp: Equatable, Sendable {
    let digest: Data
    let identity: String
    let modified: Date?
    static func read(_ url: URL) throws -> Self {
        let values = try url.resourceValues(forKeys: [.isRegularFileKey, .isSymbolicLinkKey, .fileResourceIdentifierKey, .contentModificationDateKey])
        guard values.isRegularFile == true, values.isSymbolicLink != true else { throw AudioTagError.conflict }
        let file = try FileHandle(forReadingFrom: url)
        defer { try? file.close() }
        var hash = SHA256()
        while let data = try file.read(upToCount: 1_048_576), !data.isEmpty {
            try Task.checkCancellation()
            hash.update(data: data)
        }
        return Self(digest: Data(hash.finalize()), identity: String(describing: values.fileResourceIdentifier), modified: values.contentModificationDate)
    }
}

nonisolated struct AudioTagSnapshot: Sendable {
    let document: AudioTagDocument
    let stamp: AudioTagFileStamp
}

/// This actor owns all tag I/O. NSFileCoordinator also serializes commits against
/// download import and file providers; writes are never made to the original in place.
actor AudioTagEditor {
    static let shared = AudioTagEditor()

    func read(_ url: URL, access: OfflineFolderAccess, flacOnly: Bool = false) throws -> AudioTagSnapshot {
        defer { withExtendedLifetime(access) {} }
        try validate(url, access: access)
        return try coordinated(access.url, writing: false) {
            let stamp = try AudioTagFileStamp.read(url)
            let document = try AudioTagCodec.read(url, flacOnly: flacOnly)
            guard stamp == (try AudioTagFileStamp.read(url)) else { throw AudioTagError.conflict }
            return AudioTagSnapshot(document: document, stamp: stamp)
        }
    }

    func save(_ draft: AudioTagDocument, snapshot: AudioTagSnapshot, url: URL, access: OfflineFolderAccess) throws {
        defer { withExtendedLifetime(access) {} }
        try validate(url, access: access)
        let temporary = FileManager.default.temporaryDirectory.appendingPathComponent("neodizzy-tags-\(UUID().uuidString).\(url.pathExtension)")
        defer { try? FileManager.default.removeItem(at: temporary) }
        try coordinated(access.url, writing: false) {
            guard try AudioTagFileStamp.read(url) == snapshot.stamp else { throw AudioTagError.conflict }
            try FileManager.default.copyItem(at: url, to: temporary)
        }
        try Task.checkCancellation()
        try AudioTagCodec.write(draft, original: snapshot.document, to: temporary)
        try coordinated(access.url, writing: true) {
            try validate(url, access: access)
            guard try AudioTagFileStamp.read(url) == snapshot.stamp else { throw AudioTagError.conflict }
            guard FileManager.default.isWritableFile(atPath: url.path) else { throw AudioTagError.message("文件只读，请在文件提供商中检查写入权限。") }
            // Stage beside the original so replacement stays on the provider's volume.
            let staging = url.deletingLastPathComponent().appendingPathComponent(".neodizzy-tags-\(UUID().uuidString)")
            defer { try? FileManager.default.removeItem(at: staging) }
            try FileManager.default.copyItem(at: temporary, to: staging)
            try Task.checkCancellation()
            guard try AudioTagFileStamp.read(url) == snapshot.stamp else { throw AudioTagError.conflict }
            _ = try FileManager.default.replaceItemAt(url, withItemAt: staging)
            // Once committed, cancellation must not report the file as unsaved.
        }
    }

    private func validate(_ url: URL, access: OfflineFolderAccess) throws {
        _ = try OfflinePaths.relativePath(of: url, inside: access.url)
        guard (try url.resourceValues(forKeys: [.isSymbolicLinkKey])).isSymbolicLink != true else { throw AudioTagError.conflict }
    }

    private func coordinated<T>(_ root: URL, writing: Bool, _ operation: () throws -> T) throws -> T {
        var result: Result<T, Error>?
        var error: NSError?
        let accessor: (URL) -> Void = { _ in result = Result { try operation() } }
        let coordinator = NSFileCoordinator()
        if writing { coordinator.coordinate(writingItemAt: root, options: [], error: &error, byAccessor: accessor) }
        else { coordinator.coordinate(readingItemAt: root, options: [], error: &error, byAccessor: accessor) }
        if let result { return try result.get() }
        throw error ?? CocoaError(.fileWriteUnknown)
    }
}
