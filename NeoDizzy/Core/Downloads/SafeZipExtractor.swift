import Foundation
import CoreFoundation
import ZIPFoundation

nonisolated enum SafeZipExtractor {
    struct Limits: Sendable {
        var archiveBytes: UInt64 = 4 * 1_024 * 1_024 * 1_024
        var totalBytes: UInt64 = 8 * 1_024 * 1_024 * 1_024
        var fileBytes: UInt64 = 4 * 1_024 * 1_024 * 1_024
        var entries = 10_000
        var depth = 24
    }

    static let gbk = String.Encoding(rawValue: CFStringConvertEncodingToNSStringEncoding(CFStringEncoding(CFStringEncodings.GB_18030_2000.rawValue)))

    /// Prefer valid UTF-8. Legacy encodings can both decode the same bytes to different names;
    /// use the album's published track titles to disambiguate instead of silently importing mojibake.
    /// User imports have no published titles; `preferLegacyEncoding` picks the encoding when the names give no hint.
    static func decodedPaths(_ entries: [Entry], expectedTracks: [Track], preferLegacyEncoding: String.Encoding? = nil) throws -> [String] {
        let utf8 = entries.map { $0.path(using: .utf8) }
        if utf8.allSatisfy({ !$0.isEmpty }) { return utf8 }
        var candidates: [[String]] = []
        for encoding in [gbk, .shiftJIS] {
            let paths = entries.map { $0.path(using: encoding) }
            if paths.allSatisfy({ !$0.isEmpty }), !candidates.contains(paths) { candidates.append(paths) }
        }
        guard !candidates.isEmpty else { throw DownloadFailure.unsafeArchive }
        if candidates.count == 1 { return candidates[0] }
        let titles = expectedTracks.map { normalizedTitle($0.title) }.filter { !$0.isEmpty }
        if titles.isEmpty, let preferLegacyEncoding {
            let paths = entries.map { $0.path(using: preferLegacyEncoding) }
            if paths.allSatisfy({ !$0.isEmpty }) { return paths }
        }
        let scores = candidates.map { paths in
            paths.reduce(0) { score, path in
                let stem = normalizedTitle(URL(fileURLWithPath: path).deletingPathExtension().lastPathComponent)
                return score + (titles.contains(where: { stem.contains($0) }) ? 1 : 0)
            }
        }
        guard let best = scores.max(), best > 0, scores.filter({ $0 == best }).count == 1,
              let index = scores.firstIndex(of: best) else { throw DownloadFailure.ambiguousEncoding }
        return candidates[index]
    }

    private static func normalizedTitle(_ title: String) -> String {
        title.precomposedStringWithCanonicalMapping.lowercased().unicodeScalars
            .filter { CharacterSet.alphanumerics.contains($0) }.map(String.init).joined()
    }

    static func validatePath(_ path: String, depth: Int = 24) throws -> String {
        guard !path.isEmpty, !path.hasPrefix("/"), !path.hasPrefix("\\"),
              !path.contains("\\"), !path.contains(":"),
              !path.unicodeScalars.contains(where: { $0.value < 32 || $0.value == 127 }) else {
            throw DownloadFailure.unsafeArchive
        }
        var components = path.split(separator: "/", omittingEmptySubsequences: false).map(String.init)
        if components.last == "" { components.removeLast() }
        guard !components.isEmpty, components.count <= depth,
              components.allSatisfy({ !$0.isEmpty && $0 != "." && $0 != ".." && $0.utf8.count <= 255 }) else {
            throw DownloadFailure.unsafeArchive
        }
        return components.joined(separator: "/").precomposedStringWithCanonicalMapping
    }

    static func validateZIP(_ url: URL, limits: Limits = Limits()) throws {
        let size = try url.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0
        guard size > 0, UInt64(size) <= limits.archiveBytes else { throw DownloadFailure.archiveTooLarge }
        let handle = try FileHandle(forReadingFrom: url)
        defer { try? handle.close() }
        let prefix = try handle.read(upToCount: 4)
        guard prefix == Data([0x50, 0x4b, 0x03, 0x04]) else { throw DownloadFailure.invalidResponse }
    }

    /// Removing a large extracted tree is filesystem work too; keep it off the UI actor.
    @concurrent
    static func removeTemporaryFiles(_ urls: [URL]) async {
        for url in urls { try? FileManager.default.removeItem(at: url) }
    }

    /// Extracts into a new private staging directory. The caller imports it transactionally and removes it.
    @concurrent
    static func extract(_ zip: URL, into destination: URL, limits: Limits = Limits(), expectedTracks: [Track] = [],
                        preferLegacyEncoding: String.Encoding? = nil) async throws {
        try validateZIP(zip, limits: limits)
        let manager = FileManager.default
        guard !manager.fileExists(atPath: destination.path) else { throw DownloadFailure.unsafeArchive }
        do {
            let archive = try Archive(url: zip, accessMode: .read)
            var rawEntries: [Entry] = []
            for entry in archive {
                try Task.checkCancellation()
                guard rawEntries.count < limits.entries else { throw DownloadFailure.archiveTooLarge }
                rawEntries.append(entry)
            }
            let decoded = try decodedPaths(rawEntries, expectedTracks: expectedTracks, preferLegacyEncoding: preferLegacyEncoding)
            var entries: [(Entry, String)] = []
            var paths = Set<String>()
            var advertisedTotal: UInt64 = 0
            for (entry, decodedPath) in Swift.zip(rawEntries, decoded) {
                try Task.checkCancellation()
                guard entry.type != .symlink else { throw DownloadFailure.unsafeArchive }
                let path = try validatePath(decodedPath, depth: limits.depth)
                let key = path.lowercased()
                guard paths.insert(key).inserted else { throw DownloadFailure.unsafeArchive }
                guard entries.count < limits.entries, entry.uncompressedSize <= limits.fileBytes,
                      entry.uncompressedSize <= limits.totalBytes - advertisedTotal else { throw DownloadFailure.archiveTooLarge }
                advertisedTotal += entry.uncompressedSize
                entries.append((entry, path))
            }
            guard !entries.isEmpty else { throw DownloadFailure.damagedArchive }
            try manager.createDirectory(at: destination, withIntermediateDirectories: true)
            var actualTotal: UInt64 = 0
            for (entry, path) in entries {
                try Task.checkCancellation()
                let output = destination.appendingPathComponent(path)
                if entry.type == .directory {
                    try manager.createDirectory(at: output, withIntermediateDirectories: true)
                    continue
                }
                try manager.createDirectory(at: output.deletingLastPathComponent(), withIntermediateDirectories: true)
                guard !manager.fileExists(atPath: output.path), manager.createFile(atPath: output.path, contents: nil) else {
                    throw DownloadFailure.unsafeArchive
                }
                let handle = try FileHandle(forWritingTo: output)
                defer { try? handle.close() }
                var written: UInt64 = 0
                let checksum = try archive.extract(entry, bufferSize: 64 * 1_024, skipCRC32: false) { data in
                    try Task.checkCancellation()
                    let count = UInt64(data.count)
                    guard count <= limits.fileBytes - written, count <= limits.totalBytes - actualTotal else {
                        throw DownloadFailure.archiveTooLarge
                    }
                    written += count
                    actualTotal += count
                    try handle.write(contentsOf: data)
                }
                guard checksum == entry.checksum, written == entry.uncompressedSize else { throw DownloadFailure.damagedArchive }
            }
        } catch {
            try? manager.removeItem(at: destination)
            if error is CancellationError || error is DownloadFailure { throw error }
            throw DownloadFailure.damagedArchive
        }
    }
}
