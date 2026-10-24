import Foundation
import Synchronization
import Testing
@testable import NeoDizzy

@Suite(.serialized) @MainActor
struct QQMusicPageModelTests {
    @Test func cachedAlbumArtworkIsAvailableBeforeAndDuringItsFirstDetailRequest() async throws {
        QQPageStub.state.withLock { $0 = .init(holdRequests: [2], replies: [
            .data(response(["albums": [["mid": "album", "name": "Listed album", "pic": "https://example.invalid/list-size.jpg"]], "total": 1])),
            .data(response(["basicInfo": ["name": "Loaded album"]])),
            .data(response(["songList": [], "totalNum": 0]))
        ]) }
        let store = makeStore(), cache = QQMusicContentCache()
        await cache.page(.newAlbums(1), revision: store.revision).load(store: store, route: .newAlbums(1))
        let detail = cache.page(.album("album"), revision: store.revision)
        let artwork = QQMusicSong.cover(albumMid: "album")
        #expect(detail.title == "Listed album" && detail.artwork == artwork)
        #expect(!detail.hasLoaded && detail.songs.isEmpty)
        #expect(QQPageStub.state.withLock { $0.started } == 1)

        let loading = Task { await detail.load(store: store, route: .album("album")) }
        let pending = try await heldRequest()
        #expect(detail.loading && detail.artwork == artwork && detail.title == "Listed album")
        pending.finish(data: response(["basicInfo": ["name": "Loaded album"]]))
        await loading.value
        #expect(detail.hasLoaded && detail.title == "Loaded album" && detail.artwork == artwork)
        #expect(detail.error == nil)
    }

    @Test func cachedPlaylistArtworkSurvivesItsFirstRequestFailureAndUpdatesOnRetry() async throws {
        QQPageStub.state.withLock { $0 = .init(holdRequests: [2], replies: [
            .data(recommended(["1"], next: 0, more: false)), .failure,
            .data(response(["dirinfo": ["title": "Updated playlist", "picurl": "https://example.invalid/updated.jpg"],
                            "songlist": [], "total_song_num": 0, "hasmore": 0]))
        ]) }
        let store = makeStore(), cache = QQMusicContentCache()
        await cache.page(.recommended, revision: store.revision).load(store: store, route: .recommended)
        let detail = cache.page(.playlist("1"), revision: store.revision)
        let artwork = URL(string: "https://example.invalid/1.jpg")
        #expect(detail.title == "Playlist 1" && detail.artwork == artwork && !detail.hasLoaded)
        let loading = Task { await detail.load(store: store, route: .playlist("1")) }
        let pending = try await heldRequest()
        #expect(detail.loading && detail.artwork == artwork)
        pending.fail()
        await loading.value
        #expect(detail.error != nil && detail.artwork == artwork && !detail.hasLoaded)
        await detail.load(store: store, route: .playlist("1"))
        #expect(detail.hasLoaded && detail.error == nil && detail.title == "Updated playlist")
        #expect(detail.artwork == URL(string: "https://example.invalid/updated.jpg"))
    }

    @Test func cachedPresentationIsClearedByResetAccountRevisionAndStop() async throws {
        QQPageStub.state.withLock { $0 = .init(replies: [
            .data(recommended(["1"], next: 0, more: false)), .failure
        ]) }
        let store = makeStore(), cache = QQMusicContentCache()
        await cache.page(.recommended, revision: store.revision).load(store: store, route: .recommended)
        let detail = cache.page(.playlist("1"), revision: store.revision)
        #expect(detail.artwork != nil)
        detail.reset()
        #expect(detail.artwork == nil && detail.title.isEmpty)
        await detail.load(store: store, route: .playlist("1"))
        #expect(detail.artwork == nil && detail.title.isEmpty && detail.error != nil)

        let seededAlbum = cache.page(.album("album"), revision: store.revision)
        #expect(seededAlbum.artwork != nil)
        let oldRevision = store.revision
        await store.signOut()
        let newAccount = cache.page(.playlist("1"), revision: store.revision)
        #expect(newAccount !== detail && newAccount.artwork == nil && newAccount.title.isEmpty)
        #expect(seededAlbum.artwork == nil && seededAlbum.title.isEmpty)
        #expect(cache.page(.album("album"), revision: oldRevision).artwork == nil)
        #expect(cache.page(.playlist("1"), revision: store.revision) === newAccount)

        let newAlbum = cache.page(.album("album"), revision: store.revision)
        #expect(newAlbum.artwork != nil)
        cache.stop()
        #expect(newAlbum.artwork == nil && newAlbum.title.isEmpty)
        #expect(cache.page(.album("album"), revision: store.revision).artwork == nil)
    }

    @Test func initialPresentationDoesNotSurviveLoadingADifferentRouteOrAccount() async throws {
        QQPageStub.state.withLock { $0 = .init(replies: [.failure, .failure]) }
        let store = makeStore(), cache = QQMusicContentCache()
        let differentRoute = cache.page(.album("album"), revision: store.revision)
        #expect(differentRoute.artwork != nil)
        await differentRoute.load(store: store, route: .playlist("1"))
        #expect(differentRoute.artwork == nil && differentRoute.title.isEmpty && differentRoute.error != nil)

        let oldAccount = cache.page(.album("otherAlbum"), revision: store.revision)
        #expect(oldAccount.artwork != nil)
        await store.signOut()
        await oldAccount.load(store: store, route: .album("otherAlbum"))
        #expect(oldAccount.artwork == nil && oldAccount.title.isEmpty && oldAccount.error != nil)
    }

    @Test func descriptionRefreshFailureKeepsContentAndRouteSwitchClearsIt() async {
        QQPageStub.state.withLock { $0 = .init(replies: [
            .data(response(["basicInfo": ["name": "Album", "desc": "专辑介绍"]])),
            .data(response(["songList": [], "totalNum": 0])),
            .failure,
            .data(response(["dirinfo": ["title": "Playlist", "desc": "歌单介绍"], "songlist": [], "total_song_num": 0, "hasmore": 0])),
            .data(response(["dirinfo": ["title": "Other Playlist"], "songlist": [], "total_song_num": 0, "hasmore": 0]))
        ]) }
        let store = makeStore(), model = QQMusicPageModel()
        await model.load(store: store, route: .album("album"))
        #expect(model.detailDescription == "专辑介绍" && model.hasLoaded)
        await model.load(store: store, route: .album("album"))
        #expect(model.detailDescription == "专辑介绍" && model.error != nil)
        await model.load(store: store, route: .playlist("1"))
        #expect(model.detailDescription == "歌单介绍" && model.error == nil)
        await model.load(store: store, route: .playlist("2"))
        #expect(model.detailDescription.isEmpty && model.hasLoaded)
    }

    @Test func shortSearchPageCanLoadMoreButRepeatedPageStopsWithoutDuplicates() async {
        QQPageStub.state.withLock { $0 = .init() }
        let store = makeStore(), model = QQMusicPageModel()
        await model.load(store: store, route: .search("test"))
        #expect(model.songs.count == 10 && model.more)
        await model.load(store: store, route: .search("test"), append: true)
        #expect(model.songs.count == 10 && !model.more)
        await model.load(store: store, route: .search("test"), append: true)
        #expect(QQPageStub.state.withLock { $0.started } == 2)
    }

    @Test func oldSearchCompletingAfterNewSearchCannotOverwriteNewResults() async throws {
        QQPageStub.state.withLock { $0 = .init(holdFirst: true) }
        let store = makeStore(), model = QQMusicPageModel()
        let old = Task { await model.load(store: store, route: .search("old")) }
        let pending = try await heldRequest()
        await model.load(store: store, route: .search("new"))
        #expect(model.title == "new" && model.hasLoaded)
        pending.finish(prefix: "old")
        await old.value
        #expect(model.title == "new")
        #expect(model.songs.allSatisfy { $0.mid.hasPrefix("result") })
        #expect(!model.loading)
    }

    @Test func deactivatedModuleDiscardsInFlightPageAndRejectsFurtherLoads() async throws {
        QQPageStub.state.withLock { $0 = .init(holdFirst: true) }
        let store = makeStore(), model = QQMusicPageModel()
        let loading = Task { await model.load(store: store, route: .search("test")) }
        let pending = try await heldRequest()
        store.deactivate()
        pending.finish(prefix: "disabled")
        await loading.value
        #expect(model.songs.isEmpty && !model.hasLoaded && !model.loading)
        await model.load(store: store, route: .search("again"))
        #expect(QQPageStub.state.withLock { $0.started } == 1)
    }

    @Test func recommendedPagesUseServerCursorAndStopRepeatedItems() async throws {
        QQPageStub.state.withLock { $0 = .init(replies: [
            .data(recommended(["1", "1", "2"], next: 400)),
            .data(recommended(["2", "3"], next: 750)),
            .data(recommended(["1", "2", "3"], next: 1200))
        ]) }
        let store = makeStore(), model = QQMusicPageModel()

        await model.load(store: store, route: .recommended)
        #expect(model.playlists.map(\.id) == ["1", "2"])
        #expect(model.more && model.hasLoaded)
        await model.load(store: store, route: .recommended, append: true)
        #expect(model.playlists.map(\.id) == ["1", "2", "3"])
        #expect(model.more)
        await model.load(store: store, route: .recommended, append: true)
        #expect(model.playlists.map(\.id) == ["1", "2", "3"])
        #expect(!model.more)
        await model.load(store: store, route: .recommended, append: true)

        #expect(QQPageStub.state.withLock { $0.calls.compactMap(\.cursor) } == [0, 400, 750])
        #expect(QQPageStub.state.withLock { $0.calls.compactMap(\.size) } == [30, 30, 30])
    }

    @Test func repeatedOrBackwardRecommendedCursorCannotLoop() async throws {
        for next in [0, 400] {
            QQPageStub.state.withLock { $0 = .init(replies: [
                .data(recommended(["1"], next: 400)), .data(recommended(["2"], next: next))
            ]) }
            let store = makeStore(), model = QQMusicPageModel()
            await model.load(store: store, route: .recommended)
            await model.load(store: store, route: .recommended, append: true)
            #expect(model.playlists.map(\.id) == ["1", "2"])
            #expect(!model.more)
            await model.load(store: store, route: .recommended, append: true)
            #expect(QQPageStub.state.withLock { $0.started } == 2)
        }
    }

    @Test func emptyRecommendedPageStopsEvenWhenServerAdvertisesAnotherCursor() async {
        QQPageStub.state.withLock { $0 = .init(replies: [.data(recommended([], next: 400))]) }
        let store = makeStore(), model = QQMusicPageModel()
        await model.load(store: store, route: .recommended)
        #expect(model.playlists.isEmpty && model.hasLoaded && !model.more)
        await model.load(store: store, route: .recommended, append: true)
        #expect(QQPageStub.state.withLock { $0.started } == 1)
    }

    @Test func appendFailureKeepsItemsAndRetriesTheSameServerCursor() async throws {
        QQPageStub.state.withLock { $0 = .init(replies: [
            .data(recommended(["1"], next: 400)), .failure,
            .data(recommended(["2"], next: 900, more: false))
        ]) }
        let store = makeStore(), model = QQMusicPageModel()
        await model.load(store: store, route: .recommended)
        await model.load(store: store, route: .recommended, append: true)

        #expect(model.playlists.map(\.id) == ["1"])
        #expect(model.error != nil && model.retryAppend && model.more)
        await model.load(store: store, route: .recommended, append: true)
        #expect(model.playlists.map(\.id) == ["1", "2"])
        #expect(model.error == nil && !model.more)
        #expect(QQPageStub.state.withLock { $0.calls.compactMap(\.cursor) } == [0, 400, 400])
    }

    @Test func failedRefreshKeepsLoadedContentAndOriginalAppendCursor() async throws {
        QQPageStub.state.withLock { $0 = .init(holdRequests: [2], replies: [
            .data(recommended(["1", "2"], next: 400)), .failure,
            .data(recommended(["3"], next: 900, more: false))
        ]) }
        let store = makeStore(), model = QQMusicPageModel()
        await model.load(store: store, route: .recommended)
        let refresh = Task { await model.load(store: store, route: .recommended) }
        let pending = try await heldRequest()

        #expect(model.loading && model.hasLoaded)
        #expect(model.playlists.map(\.id) == ["1", "2"])
        pending.fail()
        await refresh.value
        #expect(model.error != nil && !model.retryAppend && !model.loading)
        #expect(model.hasLoaded && model.more)
        #expect(model.playlists.map(\.id) == ["1", "2"])
        await model.load(store: store, route: .recommended, append: true)
        #expect(model.playlists.map(\.id) == ["1", "2", "3"])
        #expect(QQPageStub.state.withLock { $0.calls.compactMap(\.cursor) } == [0, 0, 400])
    }

    @Test func lateAppendCannotOverwriteRefreshOrItsNewCursor() async throws {
        QQPageStub.state.withLock { $0 = .init(holdRequests: [2], replies: [
            .data(recommended(["1"], next: 400)), .data(recommended(["2"], next: 900)),
            .data(recommended(["9"], next: 50)), .data(recommended(["10"], next: 100, more: false))
        ]) }
        let store = makeStore(), model = QQMusicPageModel()
        await model.load(store: store, route: .recommended)
        let oldAppend = Task { await model.load(store: store, route: .recommended, append: true) }
        let pending = try await heldRequest()
        await model.load(store: store, route: .recommended)
        #expect(model.playlists.map(\.id) == ["9"])

        pending.finish(data: recommended(["2"], next: 900))
        await oldAppend.value
        #expect(model.playlists.map(\.id) == ["9"])
        #expect(model.more && !model.loading)
        await model.load(store: store, route: .recommended, append: true)
        #expect(model.playlists.map(\.id) == ["9", "10"])
        #expect(QQPageStub.state.withLock { $0.calls.compactMap(\.cursor) } == [0, 400, 0, 50])
    }

    @Test func accountRevisionClearsPreviousContentBeforeLoadingReplacement() async throws {
        QQPageStub.state.withLock { $0 = .init(holdRequests: [2], replies: [
            .data(recommended(["1"], next: 400)), .data(recommended(["2"], next: 50))
        ]) }
        let store = makeStore(), model = QQMusicPageModel()
        await model.load(store: store, route: .recommended)
        await store.signOut()
        let loading = Task { await model.load(store: store, route: .recommended) }
        let pending = try await heldRequest()

        #expect(model.playlists.isEmpty && !model.hasLoaded && model.loading)
        pending.finish(data: recommended(["2"], next: 50))
        await loading.value
        #expect(model.playlists.map(\.id) == ["2"])
        #expect(QQPageStub.state.withLock { $0.calls.compactMap(\.cursor) } == [0, 0])
    }

    @Test func chartPagesKeepServerGroupsAndUseTheirRealTitles() async throws {
        let response = chartGroups()
        QQPageStub.state.withLock { $0 = .init(replies: [.data(response), .data(response), .data(response)]) }
        let store = makeStore(), model = QQMusicPageModel()
        await model.load(store: store)
        #expect(model.chartGroups.map(\.id) == ["2", "0"])
        #expect(model.charts.map(\.id) == ["50", "62", "26"])
        await model.load(store: store, route: .chartGroup("2"))
        #expect(model.title == "特色榜")
        #expect(model.chartGroups.map(\.id) == ["2"])
        #expect(model.charts.map(\.id) == ["50", "62"])
        await model.load(store: store, route: .charts)
        #expect(model.title == "排行榜")
        #expect(model.charts.map(\.id) == ["50", "62", "26"])
        #expect(!model.more)
    }

    @Test func cacheReusesLoadedPagesUntilAccountRevisionChanges() async throws {
        QQPageStub.state.withLock { $0 = .init(replies: [.data(recommended(["1"], next: 400))]) }
        let store = makeStore(), cache = QQMusicContentCache()
        let first = cache.page(.recommended, revision: 0)
        await first.load(store: store, route: .recommended)
        let reused = cache.page(.recommended, revision: 0)
        #expect(reused === first && reused.hasLoaded)
        #expect(reused.playlists.map(\.id) == ["1"])
        #expect(cache.page(.charts, revision: 0) !== first)

        let newAccount = cache.page(.recommended, revision: 1)
        #expect(newAccount !== first && !newAccount.hasLoaded)
        #expect(first.playlists.isEmpty && !first.hasLoaded && !first.more)
        _ = cache.page(.recommended, revision: 0)
        #expect(cache.page(.recommended, revision: 1) === newAccount)
        #expect(QQPageStub.state.withLock { $0.started } == 1)
    }

    @Test func cacheRevisionResetRejectsAnOldAccountsLateResponse() async throws {
        QQPageStub.state.withLock { $0 = .init(holdFirst: true, replies: [
            .data(recommended(["1"], next: 400)), .data(recommended(["2"], next: 50))
        ]) }
        let store = makeStore(), cache = QQMusicContentCache()
        let oldPage = cache.page(.recommended, revision: 0)
        let loading = Task { await oldPage.load(store: store, route: .recommended) }
        let pending = try await heldRequest()
        let newPage = cache.page(.recommended, revision: 1)
        await newPage.load(store: store, route: .recommended)
        pending.finish(data: recommended(["1"], next: 400))
        await loading.value

        #expect(oldPage.playlists.isEmpty && !oldPage.hasLoaded && !oldPage.loading)
        #expect(newPage.playlists.map(\.id) == ["2"])
        #expect(cache.page(.recommended, revision: 1) === newPage)
    }

    @Test func stoppedCacheCannotBeRepopulatedByLateResponses() async throws {
        QQPageStub.state.withLock { $0 = .init(holdFirst: true) }
        let store = makeStore(), cache = QQMusicContentCache()
        let oldPage = cache.page(.recommended, revision: 0)
        let loading = Task { await oldPage.load(store: store, route: .recommended) }
        let pending = try await heldRequest()
        cache.stop()
        pending.finish(data: recommended(["1"], next: 400))
        await loading.value

        #expect(oldPage.playlists.isEmpty && !oldPage.hasLoaded && !oldPage.loading)
        let afterStop = cache.page(.recommended, revision: 0)
        #expect(afterStop !== oldPage && !afterStop.hasLoaded)
        #expect(cache.page(.recommended, revision: 0) !== afterStop)
    }

    @Test func concurrentFirstPageCallersShareOneRequestAndSurviveFirstCallersCancellation() async throws {
        QQPageStub.state.withLock { $0 = .init(holdFirst: true) }
        let store = makeStore(), model = QQMusicPageModel()
        var firstFinished = false, secondStarted = false, secondFinished = false
        let first = Task {
            await model.load(store: store, route: .recommended)
            firstFinished = true
        }
        let pending = try await heldRequest()
        let second = Task {
            secondStarted = true
            await model.load(store: store, route: .recommended)
            secondFinished = true
        }
        while !secondStarted { await Task.yield() }
        first.cancel()
        for _ in 0..<5 { await Task.yield() }

        #expect(!firstFinished && !secondFinished)
        #expect(model.loading && !model.hasLoaded)
        #expect(QQPageStub.state.withLock { $0.started } == 1)
        #expect(pending.stopCount == 0)
        pending.finish(data: recommended(["1"], next: 400))
        await first.value
        await second.value

        #expect(firstFinished && secondFinished)
        #expect(model.playlists.map(\.id) == ["1"])
        #expect(model.hasLoaded && !model.loading && model.error == nil)
        #expect(QQPageStub.state.withLock { $0.started } == 1)
    }

    @Test func resetCancelsSharedRequestAndRejectsItsLateResponse() async throws {
        QQPageStub.state.withLock { $0 = .init(holdFirst: true, replies: [
            .data(recommended(["1"], next: 400)), .data(recommended(["2"], next: 50))
        ]) }
        let store = makeStore(), model = QQMusicPageModel()
        let first = Task { await model.load(store: store, route: .recommended) }
        let pending = try await heldRequest()
        var secondStarted = false, secondFinished = false
        let second = Task {
            secondStarted = true
            await model.load(store: store, route: .recommended)
            secondFinished = true
        }
        while !secondStarted { await Task.yield() }
        #expect(!secondFinished)
        model.reset()
        await first.value
        await second.value
        #expect(model.playlists.isEmpty && !model.hasLoaded && !model.loading)

        await model.load(store: store, route: .recommended)
        pending.finish(data: recommended(["1"], next: 400))
        #expect(model.playlists.map(\.id) == ["2"])
        #expect(model.hasLoaded && !model.loading)
        #expect(QQPageStub.state.withLock { $0.started } == 2)
        #expect(pending.stopCount >= 1)
    }

    @Test func radarPagesAdvanceAndStopAtServerHasMoreFalse() async {
        QQPageStub.state.withLock { $0 = .init(replies: [
            .data(radar(["1", "2"], more: true)), .data(radar(["2", "3"], more: false))
        ]) }
        let store = makeStore(), model = QQMusicPageModel()
        await model.load(store: store, route: .radar)
        #expect(model.songs.map(\.mid) == ["1", "2"])
        #expect(model.hasLoaded && model.more)
        await model.load(store: store, route: .radar, append: true)
        #expect(model.songs.map(\.mid) == ["1", "2", "3"])
        #expect(!model.more && model.error == nil)
        await model.load(store: store, route: .radar, append: true)
        #expect(QQPageStub.state.withLock { $0.calls.compactMap(\.page) } == [1, 2])
    }

    @Test func repeatedRadarPageStopsDespiteHasMoreAndNeverDuplicatesSongs() async {
        QQPageStub.state.withLock { $0 = .init(replies: [
            .data(radar(["1", "1", "2"], more: true)), .data(radar(["2", "3"], more: true)),
            .data(radar(["1", "2", "3"], more: true))
        ]) }
        let store = makeStore(), model = QQMusicPageModel()
        await model.load(store: store, route: .radar)
        #expect(model.songs.map(\.mid) == ["1", "2"])
        await model.load(store: store, route: .radar, append: true)
        #expect(model.more && model.songs.map(\.mid) == ["1", "2", "3"])
        await model.load(store: store, route: .radar, append: true)
        #expect(!model.more && model.songs.map(\.mid) == ["1", "2", "3"])
        await model.load(store: store, route: .radar, append: true)
        #expect(QQPageStub.state.withLock { $0.calls.compactMap(\.page) } == [1, 2, 3])
    }

    @Test func failedRadarRefreshPreservesSongsAndNextPage() async throws {
        QQPageStub.state.withLock { $0 = .init(holdRequests: [2], replies: [
            .data(radar(["1", "2"], more: true)), .failure, .data(radar(["3"], more: false))
        ]) }
        let store = makeStore(), model = QQMusicPageModel()
        await model.load(store: store, route: .radar)
        let refresh = Task { await model.load(store: store, route: .radar) }
        let pending = try await heldRequest()
        #expect(model.loading && model.hasLoaded)
        #expect(model.songs.map(\.mid) == ["1", "2"])
        pending.fail()
        await refresh.value
        #expect(model.error != nil && !model.retryAppend && !model.loading)
        #expect(model.songs.map(\.mid) == ["1", "2"])
        #expect(model.hasLoaded && model.more)
        await model.load(store: store, route: .radar, append: true)
        #expect(model.songs.map(\.mid) == ["1", "2", "3"])
        #expect(model.error == nil && !model.more)
        #expect(QQPageStub.state.withLock { $0.calls.compactMap(\.page) } == [1, 1, 2])
    }

    @Test func dailyLoadsOneCompleteListAndNeverPaginates() async {
        QQPageStub.state.withLock { $0 = .init(replies: [.data(daily(["1", "1", "2"]))]) }
        let store = makeStore(), model = QQMusicPageModel()
        await store.api.setCredential(QQMusicCredential(musicID: "123", musicKey: "synthetic-test-key"))
        await model.load(store: store, route: .daily)
        #expect(model.songs.map(\.mid) == ["1", "2"])
        #expect(model.hasLoaded && !model.more && model.error == nil)
        await model.load(store: store, route: .daily, append: true)
        #expect(QQPageStub.state.withLock { $0.started } == 1)
    }

    @Test func failedDailyRefreshPreservesLoadedList() async throws {
        QQPageStub.state.withLock { $0 = .init(holdRequests: [2], replies: [
            .data(daily(["1", "2"])), .failure
        ]) }
        let store = makeStore(), model = QQMusicPageModel()
        await store.api.setCredential(QQMusicCredential(musicID: "123", musicKey: "synthetic-test-key"))
        await model.load(store: store, route: .daily)
        let refresh = Task { await model.load(store: store, route: .daily) }
        let pending = try await heldRequest()
        #expect(model.loading && model.hasLoaded)
        #expect(model.songs.map(\.mid) == ["1", "2"])
        pending.fail()
        await refresh.value
        #expect(model.error != nil && !model.loading && !model.retryAppend)
        #expect(model.hasLoaded && !model.more)
        #expect(model.songs.map(\.mid) == ["1", "2"])
    }

    @Test func dailyCacheExpiresNextDayAndFailedRefreshKeepsAllThirtySongs() async throws {
        let calendar = Calendar.current
        let day = calendar.startOfDay(for: Date(timeIntervalSince1970: 1_800_000_000))
        let nextDay = try #require(calendar.date(byAdding: .day, value: 1, to: day))
        var now = day.addingTimeInterval(60)
        let previousIDs = (1...30).map(String.init)
        let refreshedIDs = (101...130).map(String.init)
        QQPageStub.state.withLock { $0 = .init(holdRequests: [2], replies: [
            .data(daily(previousIDs)), .failure, .data(daily(refreshedIDs))
        ]) }
        let store = makeStore(), model = QQMusicPageModel(now: { now })
        await store.api.setCredential(QQMusicCredential(musicID: "123", musicKey: "synthetic-test-key"))
        #expect(model.dailyDate == nil && model.needsDailyRefresh)

        await model.load(store: store, route: .daily)
        #expect(model.songs.map(\.mid) == previousIDs)
        #expect(model.dailyDate == day && !model.needsDailyRefresh)
        now = nextDay.addingTimeInterval(-1)
        #expect(!model.needsDailyRefresh)
        now = nextDay.addingTimeInterval(60)
        #expect(model.needsDailyRefresh)

        let refresh = Task { await model.load(store: store, route: .daily) }
        let pending = try await heldRequest()
        #expect(model.loading && model.hasLoaded)
        #expect(model.songs.map(\.mid) == previousIDs)
        #expect(model.dailyDate == day && model.needsDailyRefresh)
        pending.fail()
        await refresh.value

        #expect(model.error != nil && !model.loading)
        #expect(model.songs.map(\.mid) == previousIDs)
        #expect(model.dailyDate == day && model.needsDailyRefresh)
        await model.load(store: store, route: .daily)
        #expect(model.error == nil && model.hasLoaded)
        #expect(model.songs.map(\.mid) == refreshedIDs)
        #expect(model.dailyDate == nextDay && !model.needsDailyRefresh)
        #expect(QQPageStub.state.withLock { $0.started } == 3)

        model.reset()
        #expect(model.dailyDate == nil && model.needsDailyRefresh)
        #expect(model.songs.isEmpty && !model.hasLoaded)
    }

    @Test func dailyResponseCrossingMidnightBelongsToTheRequestDay() async throws {
        let calendar = Calendar.current
        let day = calendar.startOfDay(for: Date(timeIntervalSince1970: 1_800_000_000))
        let nextDay = try #require(calendar.date(byAdding: .day, value: 1, to: day))
        var now = nextDay.addingTimeInterval(-60)
        let previousIDs = (1...30).map(String.init)
        let refreshedIDs = (101...130).map(String.init)
        QQPageStub.state.withLock { $0 = .init(holdFirst: true, replies: [
            .data(daily(previousIDs)), .data(daily(refreshedIDs))
        ]) }
        let store = makeStore(), model = QQMusicPageModel(now: { now })
        await store.api.setCredential(QQMusicCredential(musicID: "123", musicKey: "synthetic-test-key"))
        let loading = Task { await model.load(store: store, route: .daily) }
        let pending = try await heldRequest()

        now = nextDay.addingTimeInterval(60)
        pending.finish(data: daily(previousIDs))
        await loading.value

        #expect(model.hasLoaded && model.error == nil)
        #expect(model.songs.map(\.mid) == previousIDs)
        #expect(model.dailyDate == day)
        #expect(model.needsDailyRefresh)
        await model.load(store: store, route: .daily)
        #expect(model.songs.map(\.mid) == refreshedIDs)
        #expect(model.dailyDate == nextDay && !model.needsDailyRefresh)
        #expect(QQPageStub.state.withLock { $0.started } == 2)
    }

    private func daily(_ mids: [String]) -> Data {
        response(["songlist": mids.map { ["songInfo": ["id": $0, "mid": $0, "title": "Daily \($0)"]] }])
    }

    private func radar(_ mids: [String], more: Bool) -> Data {
        response(["VecSongs": mids.map { ["Track": ["id": $0, "mid": $0, "title": "Radar \($0)"]] }, "HasMore": more])
    }

    private func recommended(_ ids: [String], next: Int, more: Bool = true) -> Data {
        let rows = ids.map { id in
            ["Playlist": ["basic": ["tid": id, "title": "Playlist \(id)", "cover": ["default_url": "https://example.invalid/\(id).jpg"]]]]
        }
        return response(["List": rows, "HasMore": more, "FromLimit": next])
    }

    private func chartGroups() -> Data {
        response(["group": [
            ["groupId": 2, "groupName": "特色榜", "toplist": [["topId": 50, "title": "新歌榜"], ["topId": 62, "title": "热歌榜"]]],
            ["groupId": 0, "groupName": "巅峰榜", "toplist": [["topId": 26, "title": "流行指数榜"]]]
        ]])
    }

    private func response(_ data: [String: Any]) -> Data {
        try! JSONSerialization.data(withJSONObject: ["code": 0, "req_0": ["code": 0, "data": data]])
    }

    private func makeStore() -> QQMusicStore {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [QQPageStub.self]
        return QQMusicStore(restoreSaved: false, api: QQMusicClient(session: URLSession(configuration: configuration)), saveCredential: { _ in })
    }

    private func heldRequest() async throws -> QQPageStub {
        for _ in 0..<300 {
            if let held = QQPageStub.state.withLock({ $0.held }) { return held }
            try await Task.sleep(for: .milliseconds(10))
        }
        throw CancellationError()
    }
}

nonisolated private final class QQPageStub: URLProtocol, @unchecked Sendable {
    enum Reply { case data(Data), failure }
    struct Call { let cursor: Int?; let size: Int?; let page: Int? }
    struct State {
        var holdFirst = false
        var holdRequests: Set<Int> = []
        var replies: [Reply] = []
        var started = 0
        var held: QQPageStub?
        var calls: [Call] = []
    }
    static let state = Mutex(State())
    // URLSession can deliver a previous test's stopLoading after shared fixture
    // state was reset. Cancellation assertions must observe their own request.
    private let stops = Mutex(0)
    var stopCount: Int { stops.withLock { $0 } }
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        let param = parameters()
        let action: (Bool, Reply?) = Self.state.withLock { state in
            state.started += 1
            state.calls.append(Call(cursor: param["From"] as? Int, size: param["Size"] as? Int, page: param["Page"] as? Int))
            if state.holdRequests.contains(state.started) || (state.holdFirst && state.started == 1) {
                state.held = self
                return (true, nil)
            }
            let reply = state.replies.indices.contains(state.started - 1) ? state.replies[state.started - 1] : nil
            return (false, reply)
        }
        guard !action.0 else { return }
        switch action.1 {
        case .data(let data): finish(data: data)
        case .failure: fail()
        case nil: finish(prefix: "result")
        }
    }
    func finish(prefix: String) {
        let songs = (0..<10).map { ["mid": "\(prefix)\($0)", "title": "Song \($0)"] }
        let data = try! JSONSerialization.data(withJSONObject: ["code": 0, "req_0": ["code": 0, "data": ["body": ["item_song": ["items": songs]]]]])
        finish(data: data)
    }
    func finish(data: Data) {
        Self.state.withLock { if $0.held === self { $0.held = nil } }
        client?.urlProtocol(self, didReceive: HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: data)
        client?.urlProtocolDidFinishLoading(self)
    }
    func fail() {
        Self.state.withLock { if $0.held === self { $0.held = nil } }
        client?.urlProtocol(self, didFailWithError: URLError(.notConnectedToInternet))
    }
    private func parameters() -> [String: Any] {
        var data = request.httpBody ?? Data()
        if data.isEmpty, let stream = request.httpBodyStream {
            stream.open()
            defer { stream.close() }
            var buffer = [UInt8](repeating: 0, count: 4096)
            while stream.hasBytesAvailable {
                let count = stream.read(&buffer, maxLength: buffer.count)
                guard count > 0 else { break }
                data.append(contentsOf: buffer.prefix(count))
            }
        }
        let json = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
        let call = json?["req_0"] as? [String: Any]
        return call?["param"] as? [String: Any] ?? [:]
    }
    override func stopLoading() { stops.withLock { $0 += 1 } }
}
