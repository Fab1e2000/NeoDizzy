import Observation

/// Pages belong to one module lifetime and account revision. Resetting pages also
/// invalidates responses already in flight, even when their transport cannot cancel.
@Observable @MainActor
final class QQMusicContentCache {
    @ObservationIgnored private var pages: [QQMusicRoute?: QQMusicPageModel] = [:]
    @ObservationIgnored private var revision: Int?
    @ObservationIgnored private var stopped = false

    func page(_ route: QQMusicRoute? = nil, revision: Int) -> QQMusicPageModel {
        guard !stopped else { return QQMusicPageModel() }
        // A view task captured before an account change must not evict the new pages.
        if let currentRevision = self.revision, revision < currentRevision { return QQMusicPageModel() }
        if self.revision != revision {
            pages.values.forEach { $0.reset() }
            pages.removeAll()
            self.revision = revision
        }
        if let page = pages[route] { return page }
        let page = QQMusicPageModel()
        pages[route] = page
        return page
    }

    func stop() {
        stopped = true
        pages.values.forEach { $0.reset() }
        pages.removeAll()
    }
}
