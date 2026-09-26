import Foundation

/// 只使用文件名中明确的曲名或曲号，不按目录枚举顺序、字母序或文件数量猜测。
nonisolated enum AudioFileMatcher {
    static let extensions: Set<String> = ["mp3", "m4a", "aac", "alac", "flac", "wav", "aiff", "aif", "caf"]

    private struct Candidate {
        let path: String
        let title: String
        let number: Int?
        let numberedTitle: String?

        init(path: String) {
            self.path = path
            let stem = URL(fileURLWithPath: path).deletingPathExtension().lastPathComponent
                .folding(options: [.widthInsensitive], locale: Locale(identifier: "en_US_POSIX"))
                .trimmingCharacters(in: .whitespacesAndNewlines)
            title = AudioFileMatcher.normalized(stem)
            // 支持 01、01. 曲名、01 - 曲名、Track 01 曲名；不把标题中的任意数字当曲号。
            let expression = try! NSRegularExpression(pattern: "^(?:track[ _.-]*)?([0-9]{1,4})(?:[\\s._\\-、．:：)）\\]]+(.*))?$", options: [.caseInsensitive])
            let range = NSRange(stem.startIndex..., in: stem)
            if let match = expression.firstMatch(in: stem, range: range),
               let numberRange = Range(match.range(at: 1), in: stem) {
                number = Int(stem[numberRange])
                if let titleRange = Range(match.range(at: 2), in: stem) {
                    numberedTitle = AudioFileMatcher.normalized(String(stem[titleRange]))
                } else {
                    numberedTitle = nil
                }
            } else {
                number = nil
                numberedTitle = nil
            }
        }
    }

    static func match(tracks: [Track], relativePaths: [String]) throws -> [String: String] {
        guard !tracks.isEmpty, Set(tracks.map(\.number)).count == tracks.count else {
            throw OfflineLibraryError.invalidManifest
        }
        let candidates = relativePaths.filter { extensions.contains(URL(fileURLWithPath: $0).pathExtension.lowercased()) }
            .map(Candidate.init)
        let knownTitles = Set(tracks.map { normalized($0.title) }.filter { !$0.isEmpty })
        var result: [String: String] = [:]
        var used: Set<String> = []
        for track in tracks {
            let title = normalized(track.title)
            let number = Int(track.number)
            let matches = candidates.filter { candidate in
                // 原始标题完全相同也允许数字标题，例如「1984」。
                if !title.isEmpty && candidate.title == title { return true }
                if let number, candidate.number == number { return true }
                return false
            }
            guard !matches.isEmpty else { throw OfflineLibraryError.missingTrack(track.title) }
            // 即使有一个更像曲名的文件，同编号下仍可能有不同格式/版本，不能自动选一个。
            guard matches.count == 1, let candidate = matches.first, !used.contains(candidate.path) else {
                throw OfflineLibraryError.ambiguousTrack(track.title)
            }
            if let numberedTitle = candidate.numberedTitle, !numberedTitle.isEmpty,
               numberedTitle != title, knownTitles.contains(numberedTitle) {
                throw OfflineLibraryError.ambiguousTrack(track.title)
            }
            result[track.number] = candidate.path
            used.insert(candidate.path)
        }
        return result
    }

    private static func normalized(_ value: String) -> String {
        let folded = value.precomposedStringWithCanonicalMapping
            .folding(options: [.caseInsensitive, .widthInsensitive], locale: Locale(identifier: "en_US_POSIX"))
        // 保留所有语言的字母和数字；不抹掉声调，避免把不同名字合并。
        return String(folded.unicodeScalars.filter { CharacterSet.alphanumerics.contains($0) })
    }
}
