import AVFoundation
import Foundation

/// System decoders only; metadata failures never turn an unplayable file into a track.
enum AudioMetadataReader {
    nonisolated static func read(_ url: URL) async throws -> AudioMetadata {
        let asset = AVURLAsset(url: url)
        guard try await asset.load(.isPlayable), !(try await asset.loadTracks(withMediaType: .audio)).isEmpty else {
            throw PlaybackError.unavailable
        }
        var result = AudioMetadata()
        let duration = try await asset.load(.duration).seconds
        if duration.isFinite, duration > 0 {
            result.duration = duration
        } else {
            // Some containers omit a duration. Require a readable audio stream before indexing.
            let file = try AVAudioFile(forReading: url)
            guard file.length > 0, file.processingFormat.sampleRate > 0 else { throw PlaybackError.unavailable }
            result.duration = Double(file.length) / file.processingFormat.sampleRate
        }
        let formats = try await asset.load(.availableMetadataFormats)
        var items = try await asset.load(.commonMetadata)
        for format in formats { items += (try? await asset.loadMetadata(for: format)) ?? [] }
        var credits = AudioArtistCredits()
        for item in items {
            try Task.checkCancellation()
            let identifier = item.identifier?.rawValue.lowercased() ?? ""
            let key = (item.key as? String)?.lowercased() ?? ""
            let name = identifier + "/" + key
            let value = (try? await item.load(.stringValue))?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            if item.commonKey == .commonKeyTitle, !value.isEmpty { result.title = value }
            if item.commonKey == .commonKeyAlbumName, !value.isEmpty { result.album = value }
            credits.add(identifier: identifier, key: key, isCommonArtist: item.commonKey == .commonKeyArtist, value: value)
            if name.contains("trck") || name.contains("trkn") || name.contains("tracknumber") {
                result.trackNumber = positiveNumber(value) ?? result.trackNumber
                if result.trackNumber == nil, let data = try? await item.load(.dataValue), data.count >= 4 {
                    result.trackNumber = positive(Int(data[2]) * 256 + Int(data[3]))
                }
            }
            if name.contains("tpos") || name.contains("disk") || name.contains("discnumber") {
                result.discNumber = positiveNumber(value) ?? result.discNumber
                if result.discNumber == nil, let data = try? await item.load(.dataValue), data.count >= 4 {
                    result.discNumber = positive(Int(data[2]) * 256 + Int(data[3]))
                }
            }
            if result.artwork == nil, item.commonKey == .commonKeyArtwork || name.contains("apic") || name.contains("covr") {
                if let data = try? await item.load(.dataValue), data.count <= 20_000_000 { result.artwork = data }
            }
        }
        // AVFoundation may expose only the first repeated Vorbis credit.
        let flac = LocalFLACTags.read(url)
        let rawArtists = flac["ARTIST"] ?? flac["ARTISTS"] ?? []
        let rawAlbumArtists = flac["ALBUMARTIST"] ?? flac["ALBUMARTISTS"] ?? []
        if !rawArtists.isEmpty || !rawAlbumArtists.isEmpty {
            var raw = AudioArtistCredits()
            for value in rawArtists { raw.add(identifier: "", key: "artist", isCommonArtist: false, value: value) }
            for value in rawAlbumArtists { raw.add(identifier: "", key: "albumartist", isCommonArtist: false, value: value) }
            if !raw.artists.isEmpty { credits.replaceArtists(with: raw.artists) }
            if !raw.albumArtists.isEmpty { credits.replaceAlbumArtists(with: raw.albumArtists) }
        }
        result.artist = credits.artists.joined(separator: " / ")
        result.albumArtist = credits.albumArtists.joined(separator: " / ")
        if let tags = try? AudioTagCodec.read(url) {
            result.title = tags.text("TITLE")
            result.album = tags.text("ALBUM")
            result.artist = (tags.values["ARTIST"] ?? []).joined(separator: " / ")
            result.albumArtist = (tags.values["ALBUMARTIST"] ?? []).joined(separator: " / ")
            result.trackNumber = positiveNumber(tags.text("TRACKNUMBER"))
            result.discNumber = positiveNumber(tags.text("DISCNUMBER"))
            result.artwork = tags.coverData
        }
        return result
    }

    nonisolated private static func creditText(_ names: [String]) -> String {
        var unique: [String] = []
        for name in names.map({ $0.trimmingCharacters(in: .whitespacesAndNewlines) }) where !name.isEmpty && !unique.contains(name) { unique.append(name) }
        return unique.joined(separator: " / ")
    }

    nonisolated private static func positiveNumber(_ value: String) -> Int? {
        value.split(separator: "/").first.flatMap { Int($0.trimmingCharacters(in: .whitespaces)) }.flatMap(positive)
    }
    nonisolated private static func positive(_ value: Int) -> Int? { value > 0 ? value : nil }
}

/// Keep album credits separate from performers. Do not split punctuation in names
/// (for example AC/DC); only NUL-separated metadata values are separate people.
nonisolated struct AudioArtistCredits {
    private(set) var artists: [String] = []
    private(set) var albumArtists: [String] = []

    mutating func replaceArtists(with values: [String]) { artists = values }
    mutating func replaceAlbumArtists(with values: [String]) { albumArtists = values }

    mutating func add(identifier: String, key: String, isCommonArtist: Bool, value: String) {
        let names = [identifier, key].map {
            $0.lowercased().filter { !$0.isWhitespace && $0 != "_" && $0 != "-" }
        }
        let albumKeys = ["tpe2", "aart", "albumartist", "albumartists"]
        let artistKeys = ["tpe1", "©art", "artist", "artists", "author", "©aut"]
        func matches(_ keys: [String]) -> Bool {
            names.contains { name in keys.contains { name == $0 || name.hasSuffix("/" + $0) } }
        }
        let isAlbum = matches(albumKeys)
        guard isAlbum || isCommonArtist || matches(artistKeys) else { return }
        for part in value.split(separator: "\0") {
            let name = part.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !name.isEmpty else { continue }
            if isAlbum {
                if !albumArtists.contains(name) { albumArtists.append(name) }
            } else if !artists.contains(name) { artists.append(name) }
        }
    }
}
