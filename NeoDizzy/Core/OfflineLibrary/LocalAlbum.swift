import Foundation

nonisolated struct LocalAlbum: Identifiable, Sendable {
    struct Entry: Sendable {
        let track: Track
        let fileURL: URL
        let discNumber: Int
        var previousTrackIDs: Set<String> = []
    }
    let id: String
    let title: String
    let artist: String
    let coverURL: URL?
    let entries: [Entry]
    var previousIDs: Set<String> = []
    var tracks: [Track] { entries.map(\.track) }
}

nonisolated struct LibraryFolder: Identifiable, Codable, Sendable {
    let id: UUID
    var name: String
    var bookmark: Data
    var issue: String?
}

nonisolated struct AudioMetadata: Codable, Sendable {
    var title: String = ""
    var album: String = ""
    var artist: String = ""
    var albumArtist: String = ""
    var trackNumber: Int?
    var discNumber: Int?
    var duration: Double?
    var artwork: Data?
}
