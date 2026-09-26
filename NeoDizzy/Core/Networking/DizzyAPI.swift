import Foundation

/// 网站页面脚本使用的 JSON 接口（`/apis/*`）。
nonisolated struct DizzyAPI: Sendable {
    static let shared = DizzyAPI()
    /// 网页每页 24 张，这里保持一致。
    static let pageSize = 24
    /// 关注动态每页的社团数，与网页一致。
    static let feedPageSize = 6

    let client: DizzyHTTPClient

    init(client: DizzyHTTPClient = .shared) {
        self.client = client
    }

    /// 首页专辑列表。`sort` 实测只有 `ad` 一种效果，固定使用。
    func discs(_ category: DiscCategory, page: Int) async throws -> Page<DiscSummary> {
        let response = try await client.json(
            DiscListResponse.self,
            path: "/apis/getdiscs/",
            query: rangeQuery(page: page) + [
                URLQueryItem(name: "sort", value: "ad"),
                URLQueryItem(name: "type", value: category.rawValue),
            ]
        )
        return Page(
            items: response.discs.map(\.summary),
            hasMore: page * Self.pageSize < response.total_count
        )
    }

    /// 登录后自动带上 token：已购专辑的曲目地址是完整版，`ihavethis` 反映是否已购。
    func discDetail(id: String) async throws -> DiscDetail {
        let query = [URLQueryItem(name: "discid", value: id)]
        guard let token = client.credentials.token else {
            return try await client.json(DiscDetailResponse.self, path: "/apis/getthisdicsinfo/", query: query).detail
        }
        do {
            return try await client.json(
                DiscDetailResponse.self,
                path: "/apis/getthisdicsinfo/",
                query: query + [URLQueryItem(name: "token", value: token)]
            ).detail
        } catch let error as DizzyError where error.isUnrecognizedResponse {
            // 带 token 拿到错误页：不带 token 再试一次。这次成功说明是 token 失效了，否则是专辑本身有问题。
            let detail = try await client.json(DiscDetailResponse.self, path: "/apis/getthisdicsinfo/", query: query).detail
            rejectToken()
            return detail
        }
    }

    /// 已关注社团的新作动态，按社团分组，每页 6 组。需要登录。
    func feed(page: Int) async throws -> Page<FeedGroup> {
        guard let token = client.credentials.token else { throw DizzyError.notLoggedIn }
        let start = (max(page, 1) - 1) * Self.feedPageSize
        do {
            let response = try await client.json(FeedResponse.self, path: "/apis/getfeed/", query: [
                URLQueryItem(name: "l", value: String(start)),
                URLQueryItem(name: "r", value: String(start + Self.feedPageSize)),
                URLQueryItem(name: "sort", value: "ad"),
                URLQueryItem(name: "token", value: token),
            ])
            return Page(items: response.labels.map(\.group), hasMore: response.canshowmore)
        } catch let error as DizzyError where error.isUnrecognizedResponse {
            rejectToken()
            throw DizzyError.sessionExpired
        }
    }

    /// 网站不再接受这个 token：之后的请求不再带它，并通知账号页提示重新登录。
    private func rejectToken() {
        debugLog("token 被网站拒绝")
        client.credentials.setToken(nil)
        NotificationCenter.default.post(name: .dizzyTokenRejected, object: nil)
    }

    /// 试听片段的时长。各专辑的试听长度不同（实测有 30 秒、76 秒），但都是 128 kbps 的 MP3，
    /// 用 HEAD 拿到文件大小就能换算，不用下载音频。
    func previewDuration(of url: URL) async throws -> TimeInterval? {
        try await client.contentLength(of: url).map(Self.previewDuration(bytes:))
    }

    static func previewDuration(bytes: Int64) -> TimeInterval {
        Double(bytes) * 8 / 128_000
    }

    func labels(page: Int) async throws -> Page<LabelSummary> {
        let response = try await client.json(
            LabelListResponse.self,
            path: "/apis/getlabels/",
            query: rangeQuery(page: page) + [URLQueryItem(name: "sort", value: "ad")]
        )
        return Page(
            items: response.labels.map(\.summary),
            hasMore: page * Self.pageSize < response.total_count
        )
    }

    /// 接口用左闭右开区间 `l`、`r` 分页。
    private func rangeQuery(page: Int) -> [URLQueryItem] {
        let start = (max(page, 1) - 1) * Self.pageSize
        return [
            URLQueryItem(name: "l", value: String(start)),
            URLQueryItem(name: "r", value: String(start + Self.pageSize)),
        ]
    }
}

// MARK: - 接口原始结构（字段名与网站一致）

nonisolated struct DiscListResponse: Decodable, Sendable {
    let total_count: Int
    let discs: [DiscJSON]
}

nonisolated struct DiscJSON: Decodable, Sendable {
    let id: String
    let title: String
    let label: String?
    let labelid: Int?
    let cover: String?
    let price: Double
    let ishires: Bool?
    let tags: [String]?
    let likes: Int?
    let onsell: Bool
    let ispreselling: Bool
    let ihavethis: Bool?

    var summary: DiscSummary {
        DiscSummary(
            id: id,
            title: title,
            coverURL: DizzyURL.image(cover),
            labelName: label,
            labelID: labelid,
            price: PriceTag(price: price, onSell: onsell, isPreselling: ispreselling),
            tags: tags ?? [],
            likes: likes,
            isHiRes: ishires ?? false,
            isOwned: ihavethis ?? false
        )
    }
}

nonisolated struct DiscDetailResponse: Decodable, Sendable {
    let disc: DiscJSON
    let release_date: String?
    let disc_description: String?
    let disc_description_2: String?
    let label_description: String?
    let hasgift: Bool?
    let tracks: [TrackJSON]

    private enum CodingKeys: String, CodingKey {
        case release_date, disc_description, disc_description_2, label_description, hasgift, tracks
    }

    init(from decoder: any Decoder) throws {
        // 详情和列表项的字段在同一层，列表部分直接复用 DiscJSON。
        disc = try DiscJSON(from: decoder)
        let container = try decoder.container(keyedBy: CodingKeys.self)
        release_date = try container.decodeIfPresent(String.self, forKey: .release_date)
        disc_description = try container.decodeIfPresent(String.self, forKey: .disc_description)
        disc_description_2 = try container.decodeIfPresent(String.self, forKey: .disc_description_2)
        label_description = try container.decodeIfPresent(String.self, forKey: .label_description)
        hasgift = try container.decodeIfPresent(Bool.self, forKey: .hasgift)
        tracks = try container.decode([TrackJSON].self, forKey: .tracks)
    }

    var detail: DiscDetail {
        let summary = disc.summary
        return DiscDetail(
            summary: summary,
            releaseDate: release_date.flatMap { $0.isEmpty ? nil : $0 },
            description: Self.clean(disc_description),
            credits: Self.clean(disc_description_2),
            labelDescription: Self.clean(label_description),
            hasGift: hasgift ?? false,
            tracks: tracks.map { $0.track(fallbackDiscID: summary.id, fallbackCover: summary.coverURL) },
            streams: tracks.reduce(into: [:]) { streams, track in
                if let url = track.url.flatMap(URL.init(string:)) {
                    streams[track.id] = url
                }
            }
        )
    }

    private static func clean(_ text: String?) -> String {
        (text ?? "")
            .replacingOccurrences(of: "\r\n", with: "\n")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

nonisolated struct TrackJSON: Decodable, Sendable {
    let discid: String?
    let id: String
    let title: String
    let authers: String?
    let album: String?
    let coverurl: String?
    let url: String?

    func track(fallbackDiscID: String, fallbackCover: URL?) -> Track {
        Track(
            discID: discid ?? fallbackDiscID,
            number: id,
            title: title,
            artists: authers ?? "",
            albumTitle: album ?? "",
            coverURL: DizzyURL.image(coverurl) ?? fallbackCover
        )
    }
}

nonisolated struct LabelListResponse: Decodable, Sendable {
    let total_count: Int
    let labels: [LabelJSON]
}

nonisolated struct LabelJSON: Decodable, Sendable {
    let labelid: Int
    let title: String
    let labelcover: String?
    let description: String?
    /// 最近作品，三个数组按下标一一对应；`covers` 是相对 CDN 的路径。
    let discs: [String]?
    let covers: [String]?
    let titles: [String]?

    var summary: LabelSummary {
        let ids = discs ?? []
        let covers = covers ?? []
        let titles = titles ?? []
        return LabelSummary(
            id: labelid,
            name: title,
            coverURL: DizzyURL.image(labelcover),
            description: (description ?? "").trimmingCharacters(in: .whitespacesAndNewlines),
            recentDiscs: ids.indices.map { index in
                DiscSummary(
                    id: ids[index],
                    title: titles.indices.contains(index) ? titles[index] : ids[index],
                    coverURL: covers.indices.contains(index) ? DizzyURL.image(covers[index]) : nil,
                    labelName: title,
                    labelID: labelid
                )
            }
        )
    }
}

nonisolated struct FeedResponse: Decodable, Sendable {
    let canshowmore: Bool
    let labels: [FeedLabelJSON]
}

nonisolated struct FeedLabelJSON: Decodable, Sendable {
    let labelid: Int
    let title: String
    let labelcover: String?
    let add_date: String?
    let discs: [FeedDiscJSON]

    var group: FeedGroup {
        FeedGroup(
            labelID: labelid,
            labelName: title,
            labelCoverURL: DizzyURL.image(labelcover),
            addDate: add_date,
            discs: discs.map { $0.summary(labelName: title, labelID: labelid) }
        )
    }
}

/// 关注动态里的专辑只有这些字段，没有在售状态。
nonisolated struct FeedDiscJSON: Decodable, Sendable {
    let id: String
    let title: String
    let cover: String?
    let price: Double?
    let tags: [String]?
    let release_date: String?

    func summary(labelName: String, labelID: Int) -> DiscSummary {
        DiscSummary(
            id: id,
            title: title,
            coverURL: DizzyURL.image(cover),
            labelName: labelName,
            labelID: labelID,
            price: price.map { PriceTag(price: $0, onSell: true, isPreselling: false) },
            tags: tags ?? []
        )
    }
}
