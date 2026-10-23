import Foundation

/// A collection is complete only when every advertised row has been received.
/// Consumers use that guarantee for downloads and portable library exports.
nonisolated struct QQMusicCollectionPagination {
    private(set) var offset = 0
    private var total: Int?
    private var seen = Set<String>()

    mutating func append(_ songs: [QQMusicSong], total value: Any?, hasMore: Bool? = nil) throws -> Bool {
        let count = try Self.count(value)
        guard total == nil || total == count else { throw QQMusicError.invalidResponse }
        total = count
        let ids = Set(songs.map(\.mid))
        guard ids.count == songs.count, seen.isDisjoint(with: ids),
              songs.count <= count - offset else { throw QQMusicError.invalidResponse }
        let next = offset + songs.count
        guard !songs.isEmpty || next == count else { throw QQMusicError.invalidResponse }
        if let hasMore, hasMore != (next < count) { throw QQMusicError.invalidResponse }
        seen.formUnion(ids)
        offset = next
        return next == count
    }

    static func count(_ value: Any?) throws -> Int {
        guard let number = value as? NSNumber, String(cString: number.objCType) != "c",
              let count = Int(number.stringValue), count >= 0 else { throw QQMusicError.invalidResponse }
        return count
    }

    static func hasMore(_ value: Any?) throws -> Bool {
        guard let number = value as? NSNumber,
              number == 0 || number == 1 else { throw QQMusicError.invalidResponse }
        return number.boolValue
    }
}
