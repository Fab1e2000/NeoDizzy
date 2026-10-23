import Foundation
import Observation

@Observable
final class DiscDetailModel {
    let id: String
    let detail: Loadable<DiscDetail>
    /// 曲号 → 完整版时长，来自专辑页 HTML。取不到时为空，不影响页面。
    private(set) var durations: [String: TimeInterval] = [:]
    /// 曲号 → 试听片段时长。未购买时列表显示这个长度。
    private(set) var previewDurations: [String: TimeInterval] = [:]
    private var hasRequestedDurations = false
    private var hasRequestedPreviewDurations = false

    /// `prefetched` 是已经提前开始的请求（Mac 版悬停封面时预取），只用于第一次加载：
    /// 重试和刷新必须重新请求，否则会一直拿到同一个失败结果或过期的播放地址。
    init(id: String, fresh: Bool = false, prefetched: (() async throws -> DiscDetail)? = nil) {
        self.id = id
        var prefetched = prefetched
        detail = Loadable {
            if let load = prefetched {
                prefetched = nil
                return try await load()
            }
            return try await DizzyAPI.shared.discDetail(id: id, fresh: fresh)
        }
    }

    /// 成功取到一次就不再请求，即使页面里本来就没有时长；失败或被取消时下次进入再取。
    func loadDurations() async {
        guard !hasRequestedDurations else { return }
        guard let durations = try? await DizzyPages.shared.trackDurations(discID: id) else { return }
        self.durations = durations
        hasRequestedDurations = true
    }

    /// 每个试听文件发一个 HEAD 请求取大小，换算成时长。
    func loadPreviewDurations(for detail: DiscDetail) async {
        guard !hasRequestedPreviewDurations else { return }
        let previews = detail.streams.filter { DizzyURL.isPreviewStream($0.value) }
        guard !previews.isEmpty else {
            hasRequestedPreviewDurations = true
            return
        }
        let results = await withTaskGroup(of: (String, TimeInterval?).self) { group in
            for (number, url) in previews {
                group.addTask { (number, try? await DizzyAPI.shared.previewDuration(of: url)) }
            }
            var results: [String: TimeInterval] = [:]
            for await (number, duration) in group {
                results[number] = duration
            }
            return results
        }
        previewDurations = results
        hasRequestedPreviewDurations = !results.isEmpty
    }

    func tracks(of detail: DiscDetail) -> [Track] {
        detail.tracks.map { track in
            var track = track
            let isPreview = detail.streams[track.number].map(DizzyURL.isPreviewStream) ?? false
            track.duration = isPreview ? previewDurations[track.number] : durations[track.number]
            return track
        }
    }
}
