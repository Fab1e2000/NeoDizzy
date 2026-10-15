import Foundation

/// 由 AppDelegate 持有一次，后台唤醒时也能恢复下载，不依赖某个页面出现。iOS 与 macOS 共用。
final class AppServices {
    let neteaseDownloads: NeteaseDownloadProvider
    let netease: NeteaseStore
    let dizzyLab: DizzyLabServices
    var browsingHistory: BrowsingHistoryStore { dizzyLab.browsingHistory }
    var account: AccountStore { dizzyLab.account }
    let offlineLibrary: OfflineLibraryStore
    var downloads: DownloadStore { dizzyLab.downloads }
    var purchases: PurchaseStore { dizzyLab.purchases }
    let player: PlayerStore
    /// 手动加入资料库的在线歌曲、专辑和歌单。
    let savedLibrary = SavedLibraryStore()

    init() {
        #if os(iOS)
        // 「文件 › 我的 iPhone › NeoDizzy」就是 App 的 Documents 文件夹，下载和导入都存在这里。
        let library = OfflineLibraryStore(libraryRoot: .documentsDirectory)
        #else
        let library = OfflineLibraryStore()
        #endif
        offlineLibrary = library
        dizzyLab = DizzyLabServices(library: library)
        netease = NeteaseStore()
        neteaseDownloads = NeteaseDownloadProvider(api: netease.api, library: library)
        neteaseDownloads.playlistCompleted = { [weak library] title, id, tracks in
            guard let library else { return }
            try await library.savePlaylist(title: title, tracks: tracks,
                                           source: LibrarySource(provider: "netease", kind: "playlist", id: id))
        }
        dizzyLab.downloads.register(neteaseDownloads)
        let resolver = StreamResolver(localFile: { [weak library] track in
            library?.localFile(for: track)
        }, localAccess: { [weak library] track in
            library?.access(for: track)
        })
        let api = netease.api
        resolver.register("netease", stream: { try await api.stream($0) }, lyrics: { try await api.lyrics($0) })
        player = PlayerStore(resolver: resolver)
        let reporter = netease.reporter
        player.reporting.onStart = { [weak reporter] track, source in reporter?.started(track, sourceID: source) }
        player.reporting.onFinish = { [weak reporter] track, source, seconds in reporter?.finished(track, sourceID: source, seconds: seconds) }
        netease.playbackSettings.changed = { [weak player] in player?.remoteQualityDidChange(providerID: "netease") }
        let radio = netease.radio
        player.registerDiscovery("netease") { try await radio.next() }
        netease.accountChanged = { [weak player] in player?.remoteAccountDidChange(providerID: "netease") }
    }

    func restore() async {
        await offlineLibrary.restore()
        await dizzyLab.restore()
        player.restore()
    }
}
