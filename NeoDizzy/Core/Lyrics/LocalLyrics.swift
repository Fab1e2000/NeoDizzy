import AVFoundation
import CryptoKit
import Foundation

nonisolated struct LyricLine: Identifiable, Equatable, Sendable {
    let id: Int
    let time: TimeInterval
    let text: String
}

nonisolated struct LocalLyrics: Equatable, Sendable {
    var lines: [LyricLine]
    var plainText: String
    var source: String = ""
    var isTimed: Bool { !lines.isEmpty }
    var isEmpty: Bool { lines.isEmpty && plainText.isEmpty }

    func activeLine(at time: TimeInterval) -> Int? {
        // Upper bound also handles repeated timestamps deterministically.
        var low = 0, high = lines.count
        while low < high {
            let middle = (low + high) / 2
            if lines[middle].time <= time { low = middle + 1 } else { high = middle }
        }
        return low > 0 ? lines[low - 1].id : nil
    }

    static func parse(_ text: String) -> LocalLyrics {
        let timestamp = try! NSRegularExpression(pattern: #"\[(\d{1,3}):([0-5]?\d)(?:[.:](\d{1,3}))?\]"#)
        let offsetPattern = try! NSRegularExpression(pattern: #"\[offset:\s*([+-]?\d+)\]"#, options: .caseInsensitive)
        let fullRange = NSRange(text.startIndex..., in: text)
        let offset = offsetPattern.firstMatch(in: text, range: fullRange)
            .flatMap { Range($0.range(at: 1), in: text) }.flatMap { Double(text[$0]) }.map { $0 / 1000 } ?? 0
        var timed: [(Double, String, Int)] = []
        var plain: [String] = []
        for raw in text.replacingOccurrences(of: "\u{FEFF}", with: "").components(separatedBy: .newlines) {
            let row = raw.trimmingCharacters(in: .whitespacesAndNewlines)
            let matches = timestamp.matches(in: row, range: NSRange(row.startIndex..., in: row))
            if let last = matches.last, let end = Range(last.range, in: row)?.upperBound {
                let words = String(row[end...]).trimmingCharacters(in: .whitespaces)
                for match in matches {
                    func capture(_ n: Int) -> String {
                        Range(match.range(at: n), in: row).map { String(row[$0]) } ?? ""
                    }
                    let minutes = Double(capture(1)) ?? 0
                    let seconds = Double(capture(2)) ?? 0
                    let fraction = Double("0." + capture(3)) ?? 0
                    timed.append((max(0, minutes * 60 + seconds + fraction + offset), words, timed.count))
                }
            } else if !row.isEmpty && row.range(of: #"^\[(ar|ti|al|by|offset|length|re|ve):.*\]$"#, options: [.regularExpression, .caseInsensitive]) == nil {
                plain.append(row)
            }
        }
        timed.sort { $0.0 == $1.0 ? $0.2 < $1.2 : $0.0 < $1.0 }
        // Original and translated lines at the same timestamp are displayed together.
        var grouped: [(Double, String)] = []
        for (time, words, _) in timed {
            if grouped.last?.0 == time {
                if !words.isEmpty { grouped[grouped.count - 1].1 += "\n" + words }
            } else { grouped.append((time, words)) }
        }
        return LocalLyrics(lines: grouped.enumerated().map { LyricLine(id: $0.offset, time: $0.element.0, text: $0.element.1) },
                           plainText: plain.joined(separator: "\n"))
    }
}

nonisolated enum LocalLyricsError: LocalizedError {
    case invalidFile
    case tooLarge
    var errorDescription: String? {
        switch self {
        case .invalidFile: "无法读取歌词，请选择 UTF-8 或 UTF-16 编码的 LRC / TXT 文件。"
        case .tooLarge: "歌词文件过大，请选择小于 1 MB 的文本文件。"
        }
    }
}

/// Only local files are read. Imported lyrics live in app storage, never in music folders.
actor LocalLyricsReader {
    static let shared = LocalLyricsReader()
    private let directory: URL
    init(directory: URL = URL.applicationSupportDirectory.appendingPathComponent("Lyrics", isDirectory: true)) {
        self.directory = directory
    }

    func load(trackID: String, audioURL: URL?, access: OfflineFolderAccess?) async throws -> LocalLyrics {
        defer { withExtendedLifetime(access) {} }
        try Task.checkCancellation()
        let imported = savedURL(trackID)
        if FileManager.default.fileExists(atPath: imported.path) {
            var lyrics = try Self.read(imported)
            lyrics.source = "已导入歌词"
            return lyrics
        }
        guard let audioURL, audioURL.isFileURL, let access else {
            return LocalLyrics(lines: [], plainText: "")
        }
        _ = try OfflinePaths.relativePath(of: audioURL, inside: access.url)
        let folder = audioURL.deletingLastPathComponent()
        let stem = audioURL.deletingPathExtension().lastPathComponent.precomposedStringWithCanonicalMapping
        let files = try FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: [.isSymbolicLinkKey, .isRegularFileKey])
        let sidecars = files.filter {
            $0.pathExtension.lowercased() == "lrc" &&
            $0.deletingPathExtension().lastPathComponent.precomposedStringWithCanonicalMapping == stem &&
            (try? $0.resourceValues(forKeys: [.isSymbolicLinkKey]).isSymbolicLink) == false
        }.sorted { $0.path < $1.path }
        var sidecarError: Error?
        for url in sidecars {
            do {
                _ = try OfflinePaths.relativePath(of: url, inside: access.url)
                var lyrics = try Self.read(url)
                if !lyrics.isEmpty { lyrics.source = "同目录 LRC"; return lyrics }
            } catch { sidecarError = error }
        }
        let asset = AVURLAsset(url: audioURL)
        if let text = try await asset.load(.lyrics), text.utf8.count <= 1_048_576 {
            var lyrics = LocalLyrics.parse(text)
            if !lyrics.isEmpty { lyrics.source = "内嵌歌词"; return lyrics }
        }
        for format in try await asset.load(.availableMetadataFormats) {
            for item in try await asset.loadMetadata(for: format) {
                try Task.checkCancellation()
                let name = ((item.identifier?.rawValue ?? "") + "/" + (item.key as? String ?? "")).lowercased()
                guard name.contains("lyrics") || name.contains("uslt") || name.contains("©lyr") || name.contains("%a9lyr") else { continue }
                if let text = try await item.load(.stringValue), text.utf8.count <= 1_048_576 {
                    var lyrics = LocalLyrics.parse(text)
                    if !lyrics.isEmpty { lyrics.source = "内嵌歌词"; return lyrics }
                }
            }
        }
        if let sidecarError { throw sidecarError }
        return LocalLyrics(lines: [], plainText: "")
    }

    func importFile(_ url: URL, trackID: String) throws {
        let scoped = url.startAccessingSecurityScopedResource()
        defer { if scoped { url.stopAccessingSecurityScopedResource() } }
        let lyrics = try Self.read(url)
        guard !lyrics.isEmpty else { throw LocalLyricsError.invalidFile }
        let data = try Self.data(url)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try data.write(to: savedURL(trackID), options: .atomic)
    }

    private func savedURL(_ trackID: String) -> URL {
        let key = SHA256.hash(data: Data(trackID.utf8)).map { String(format: "%02x", $0) }.joined()
        return directory.appendingPathComponent(key + ".lrc")
    }

    nonisolated private static func data(_ url: URL) throws -> Data {
        let values = try url.resourceValues(forKeys: [.isRegularFileKey, .fileSizeKey])
        guard values.isRegularFile == true else { throw LocalLyricsError.invalidFile }
        guard (values.fileSize ?? 0) <= 1_048_576 else { throw LocalLyricsError.tooLarge }
        let handle = try FileHandle(forReadingFrom: url)
        defer { try? handle.close() }
        let data = try handle.read(upToCount: 1_048_577) ?? Data()
        guard data.count <= 1_048_576 else { throw LocalLyricsError.tooLarge }
        return data
    }

    nonisolated static func read(_ url: URL) throws -> LocalLyrics {
        let data = try data(url)
        let encoding: String.Encoding = data.starts(with: [0xff, 0xfe]) || data.starts(with: [0xfe, 0xff]) ? .utf16 : .utf8
        guard let text = String(data: data, encoding: encoding), !text.contains("\0") else { throw LocalLyricsError.invalidFile }
        return LocalLyrics.parse(text)
    }
}
