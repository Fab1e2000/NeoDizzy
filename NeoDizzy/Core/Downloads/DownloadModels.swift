import Foundation

/// A menu choice, not a cached authorization: enqueue and retry always fetch a new page.
nonisolated struct DownloadOption: Identifiable, Hashable, Sendable {
    let title: String
    let format: String
    let url: URL
    var id: String { format }
}

nonisolated enum DownloadFailure: LocalizedError {
    case ambiguousEncoding, folderMissing, unavailable, invalidResponse, unsafeArchive, archiveTooLarge, damagedArchive, interrupted

    var errorDescription: String? {
        switch self {
        case .ambiguousEncoding: "无法确定 ZIP 文件名编码，请在电脑解压后导入音乐库"
        case .folderMissing: "请先在音乐库选择保存文件夹"
        case .unavailable: "下载链接不可用，请确认已登录并已购买此专辑"
        case .invalidResponse: "网站没有返回 ZIP 文件，登录或下载链接可能已失效"
        case .unsafeArchive: "压缩包包含不安全或无法识别的文件路径"
        case .archiveTooLarge: "压缩包超过安全解压上限"
        case .damagedArchive: "ZIP 文件损坏或格式不受支持"
        case .interrupted: "下载已中断，可以重试"
        }
    }
}

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

nonisolated struct DownloadJob: Identifiable, Codable, Sendable {
    enum State: String, Codable, Sendable {
        case queued, preparing, downloading, extracting, importing, completed, cancelled, failed
        var isActive: Bool { [.queued, .preparing, .downloading, .extracting, .importing].contains(self) }
    }

    let id: UUID
    let album: DownloadAlbum
    let format: String
    var state: State = .queued
    var progress: Double?
    var failureMessage: String?
    var discID: String { album.id }
    var title: String { album.title }
    var isActive: Bool { state.isActive }
    var canRetry: Bool { state == .failed || state == .cancelled }
    var statusText: String {
        switch state {
        case .queued: "等待下载"
        case .preparing: "正在获取下载链接"
        case .downloading: "正在下载"
        case .extracting: "正在解压"
        case .importing: "正在保存到音乐库"
        case .completed: "已下载"
        case .cancelled: "已取消"
        case .failed: failureMessage ?? "下载失败，请重试"
        }
    }
}
