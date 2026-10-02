// Adapted from MeloX_Modified/Core/LocalMusic/LocalTrackMetadata.swift (GPL-3.0).
// Keeps only the embedded FLAC comment reader; sidecar metadata is not read.
import Foundation

nonisolated enum LocalFLACTags {
    /// AVFoundation does not expose every Vorbis artist/album-artist field.
    static func read(_ url: URL) -> [String: [String]] {
        guard let file = try? FileHandle(forReadingFrom: url) else { return [:] }
        defer { try? file.close() }
        guard (try? file.read(upToCount: 4)) == Data("fLaC".utf8) else { return [:] }
        for _ in 0..<128 {
            guard let header = try? file.read(upToCount: 4), header.count == 4 else { return [:] }
            let count = Int(header[1]) << 16 | Int(header[2]) << 8 | Int(header[3])
            if header[0] & 0x7F == 4 {
                guard count <= 4 * 1_024 * 1_024,
                      let data = try? file.read(upToCount: count), data.count == count else { return [:] }
                return parse(data)
            }
            guard header[0] & 0x80 == 0 else { return [:] }
            guard let position = try? file.offset() else { return [:] }
            do { try file.seek(toOffset: position + UInt64(count)) } catch { return [:] }
        }
        return [:]
    }

    static func parse(_ data: Data) -> [String: [String]] {
        var offset = 0
        func number() -> Int? {
            guard offset + 4 <= data.count else { return nil }
            defer { offset += 4 }
            return (0..<4).reduce(0) { $0 | (Int(data[offset + $1]) << ($1 * 8)) }
        }
        guard let vendorSize = number(), vendorSize <= data.count - offset else { return [:] }
        offset += vendorSize
        guard let count = number(), count <= 10_000 else { return [:] }
        var values: [String: [String]] = [:]
        for _ in 0..<count {
            guard let length = number(), length <= data.count - offset else { return [:] }
            defer { offset += length }
            guard let entry = String(data: data[offset..<offset + length], encoding: .utf8),
                  let separator = entry.firstIndex(of: "=") else { continue }
            let key = entry[..<separator].uppercased().replacingOccurrences(of: " ", with: "").replacingOccurrences(of: "_", with: "")
            let value = entry[entry.index(after: separator)...].trimmingCharacters(in: .whitespacesAndNewlines)
            if !value.isEmpty { values[key, default: []].append(value) }
        }
        return values
    }
}
