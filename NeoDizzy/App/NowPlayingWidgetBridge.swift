import Nuke
import UIKit
import WidgetKit

/// 换歌时把歌曲信息和缩小后的封面写进 App Group，再让「正在播放」小组件刷新。
enum NowPlayingWidgetBridge {
    /// 小号小组件约 170 点见方，3x 屏约 510 像素。
    private static let artworkPixels: CGFloat = 512

    static func update(for track: Track?) async {
        guard let track else {
            guard NowPlayingWidgetData.load() != nil else { return }
            write(nil, artwork: nil)
            return
        }
        // 同一首歌只补全了时长等信息时不重写，冷启动恢复队列也不会重复编码封面。
        if let saved = NowPlayingWidgetData.load(), saved.trackID == track.id,
           saved.hasArtwork || track.coverURL == nil { return }

        var artwork: Data?
        if let url = track.coverURL {
            var request = ImageRequest(url: url)
            request.thumbnail = ImageRequest.ThumbnailOptions(
                size: CGSize(width: artworkPixels, height: artworkPixels), unit: .pixels, contentMode: .aspectFill)
            artwork = try? await ImagePipeline.shared.image(for: request).jpegData(compressionQuality: 0.85)
        }
        // 取封面期间又换了歌，交给新的那次更新。
        guard !Task.isCancelled else { return }
        let snapshot = NowPlayingWidgetData.Snapshot(trackID: track.id, title: track.title,
                                                     artists: track.artists, hasArtwork: artwork != nil)
        write(snapshot, artwork: artwork)
    }

    private static func write(_ snapshot: NowPlayingWidgetData.Snapshot?, artwork: Data?) {
        do {
            try NowPlayingWidgetData.save(snapshot, artwork: artwork)
            WidgetCenter.shared.reloadTimelines(ofKind: NowPlayingWidgetData.widgetKind)
        } catch {
            debugLog("小组件数据写入失败（App Group 不可用？）：\(error.localizedDescription)")
        }
    }
}
