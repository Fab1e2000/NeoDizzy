import Foundation

/// Persists only album metadata and the format. Signed URLs, cookies and streaming URLs are excluded.
nonisolated struct DownloadAlbum: Codable, Sendable {
    let id: String
    let title: String
    let coverURL: URL?
    let labelName: String?
    let tracks: [Track]
    let releaseDate: String?
    let description: String
    let credits: String
    let labelDescription: String
    let hasGift: Bool

    init(_ detail: DiscDetail) {
        id = detail.id
        title = detail.summary.title
        coverURL = detail.summary.coverURL
        labelName = detail.summary.labelName
        tracks = detail.tracks
        releaseDate = detail.releaseDate
        description = detail.description
        credits = detail.credits
        labelDescription = detail.labelDescription
        hasGift = detail.hasGift
    }

    var detail: DiscDetail {
        DiscDetail(summary: DiscSummary(id: id, title: title, coverURL: coverURL, labelName: labelName, isOwned: true),
                   releaseDate: releaseDate, description: description, credits: credits, labelDescription: labelDescription, hasGift: hasGift,
                   tracks: tracks, streams: [:])
    }
}

