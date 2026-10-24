import Foundation
import Observation

/// Pages belong to one module lifetime and account revision. Resetting pages also
/// invalidates responses already in flight, even when their transport cannot cancel.
@Observable @MainActor
final class QQMusicContentCache {
    @ObservationIgnored private var pages: [QQMusicRoute?: QQMusicPageModel] = [:]
    @ObservationIgnored private var revision: Int?
    @ObservationIgnored private var stopped = false

    func page(_ route: QQMusicRoute? = nil, revision: Int, library: QQMusicLibrary? = nil) -> QQMusicPageModel {
        guard !stopped else { return QQMusicPageModel() }
        // A view task captured before an account change must not evict the new pages.
        if let currentRevision = self.revision, revision < currentRevision { return QQMusicPageModel() }
        if self.revision != revision {
            pages.values.forEach { $0.reset() }
            pages.removeAll()
            self.revision = revision
        }
        if let page = pages[route] { return page }
        let page = QQMusicPageModel(presentation: presentation(for: route, revision: revision, library: library))
        pages[route] = page
        return page
    }

    /// Navigation carries stable IDs; reuse the artwork already shown by that
    /// account's lists so the detail background has its cache key on the first frame.
    private func presentation(for route: QQMusicRoute?, revision: Int,
                              library: QQMusicLibrary?) -> QQMusicPageModel.InitialPresentation? {
        guard let route else { return nil }
        let collection: QQMusicCollection?
        switch route {
        case .album(let id):
            if let album = pages.values.lazy.flatMap(\.albums).first(where: { $0.id == id }) {
                collection = .init(id: id, title: album.title, coverURL: QQMusicSong.cover(albumMid: id))
            } else if let album = library?.albums.first(where: { $0.id == id }) {
                collection = album.collection
            } else if let song = pages.values.lazy.flatMap(\.songs).first(where: { $0.albumMid == id }) {
                collection = .init(id: id, title: song.albumTitle, coverURL: song.coverURL)
            } else {
                collection = .init(id: id, title: route.title, coverURL: QQMusicSong.cover(albumMid: id))
            }
        case .playlist(let id):
            collection = pages.values.lazy.flatMap(\.playlists).first(where: { $0.id == id })
                ?? library?.playlists.first(where: { $0.id == id })?.collection
        case .chart(let id):
            collection = pages.values.lazy.flatMap(\.charts).first(where: { $0.id == id })
        default:
            collection = nil
        }
        guard let collection else { return nil }
        return .init(route: route, revision: revision, title: collection.title, artwork: collection.coverURL)
    }

    func stop() {
        stopped = true
        pages.values.forEach { $0.reset() }
        pages.removeAll()
    }
}
