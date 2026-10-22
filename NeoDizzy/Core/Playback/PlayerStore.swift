import AVFoundation
import Foundation

/// 播放器：当前播放器和一个静音预缓冲播放器，加一个播放队列。迷你播放器、播放页和系统媒体控制共用这一份状态。
/// 结构参考 MeloX 的 PlayerStore，去掉了歌词、AutoMix、音质选择等 M1 用不到的部分。
@Observable
final class PlayerStore {
    private(set) var currentTrack: Track?
    /// 用户想要播放。缓冲时仍为 true，播放按钮据此显示暂停。
    private(set) var isPlaying = false
    private(set) var progress: TimeInterval = 0
    /// 当前音频的实际时长，试听曲目就是试听片段的长度。加载完成前为 0。
    private(set) var duration: TimeInterval = 0
    private(set) var isPreview = false
    private(set) var issue: String?
    private(set) var repeatMode: RepeatMode = .off
    #if os(macOS)
    /// Mac 版自带音量滑块（与 Music 相同），只调节本 App 的输出音量。
    var volume: Float = UserDefaults.standard.object(forKey: "player.volume") as? Float ?? 1 {
        didSet {
            player.volume = min(max(volume, 0), 1)
            UserDefaults.standard.set(player.volume, forKey: "player.volume")
        }
    }

    /// AirPlay 选择器（AVRoutePickerView）需要直接引用播放器。
    var routingPlayer: AVPlayer { player }
    #endif
    let reporting = PlaybackReportingSession()
    private(set) var isHeartMode = false
    private var queueSourceID: Int?
    private var queue = PlaybackQueue()
    private var loadedFileURL: URL?
    private var tagWritePaths = Set<String>()

    func holdsFile(_ url: URL) -> Bool {
        let path = LocalLibraryScanner.canonical(url)
        if let loadedFileURL, LocalLibraryScanner.canonical(loadedFileURL) == path { return true }
        return isResolving && currentTrack.flatMap { resolver.localURL(for: $0) }.map { LocalLibraryScanner.canonical($0) == path } == true
    }

    func stopForTagEditing(_ url: URL) {
        guard holdsFile(url) else { return }
        pause()
        loadGeneration += 1
        loadTask?.cancel()
        loadTask = nil
        itemStatusObservation = nil
        player.replaceCurrentItem(with: nil)
        loadedFileURL = nil
        resolver.releaseLocalAccess()
        isResolving = false
        isBuffering = false
        pendingSeek = progress
        saveState()
    }

    func beginTagWrite(_ url: URL) throws {
        guard !holdsFile(url), !tagWritePaths.contains(LocalLibraryScanner.canonical(url)) else {
            throw AudioTagError.message("请先停止此曲目的播放，再保存标签。")
        }
        tagWritePaths.insert(LocalLibraryScanner.canonical(url))
    }
    func endTagWrite(_ url: URL) { tagWritePaths.remove(LocalLibraryScanner.canonical(url)) }

    func refreshMetadata(_ tracks: [Track]) {
        let replacements = Dictionary(tracks.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        queue.updateMetadata(replacements)
        if let id = currentTrack?.id, let updated = replacements[id] {
            currentTrack = updated
            nowPlaying.setTrack(updated, duration: duration > 0 ? duration : updated.duration ?? 0,
                                queueIndex: queue.position, queueCount: queue.tracks.count)
            updateNowPlaying()
        }
        saveState()
    }

    private(set) var isDiscovery = false
    private var remoteDiscoveryID: String?
    private var remoteDiscoverySources: [String: () async throws -> Track] = [:]

    func registerDiscovery(_ id: String, next: @escaping () async throws -> Track) {
        remoteDiscoverySources[id] = next
    }
    func playRemoteDiscovery(_ track: Track, providerID: String) {
        isHeartMode = false
        queueSourceID = nil
        cancelDiscoveryRequest()
        remoteDiscoveryID = providerID
        isDiscovery = true
        queue.restore(tracks: [track], currentIndex: 0, isShuffled: false, shuffledOrder: [])
        load(autoplay: true)
    }

    private var isFetchingDiscovery = false
    @ObservationIgnored private var discoveryTask: Task<Void, Never>?
    @ObservationIgnored private var discoveryGeneration = 0
    @ObservationIgnored private var discoveryPrefetch: Task<PreparedDiscovery, Error>?

    /// A silent standby player is promoted intact, preserving its media pipeline.
    @ObservationIgnored private var preparedDiscovery: PreparedDiscovery?
    /// Read-only preparation diagnostic; no timer or additional network requests.
    var bufferedDiscoveryTrack: Track? {
        guard let next = preparedDiscovery, next.item.status == .readyToPlay,
              next.item.loadedTimeRanges.contains(where: { $0.timeRangeValue.duration.seconds > 0 }) else { return nil }
        return next.track
    }

    private final class PreparedDiscovery {
        let track: Track
        let url: URL
        let item: AVPlayerItem
        var cacheJob: UUID?
        private let staging: AVPlayer
        private var observation: NSKeyValueObservation?
        private var beganPreroll = false

        init(track: Track, url: URL, staging: AVPlayer, resolver: StreamResolver) {
            self.track = track
            self.url = url
            if !url.isFileURL, !resolver.isPreview(for: track, url: url),
               let key = resolver.audioCacheKey(for: track), let actual = resolver.actualQuality(for: track),
               let cached = AudioPlaybackCache.shared.makeItem(url: url, key: key, actualQuality: actual) {
                item = cached.0; cacheJob = cached.1
            } else { item = AVPlayerItem(url: url) }
            item.preferredForwardBufferDuration = 8
            self.staging = staging
            staging.replaceCurrentItem(with: item)
            staging.isMuted = true
            observation = staging.observe(\.status, options: [.initial, .new]) { [weak self] _, _ in
                Task { @MainActor [weak self] in
                    guard let self, !self.beganPreroll, self.staging.status == .readyToPlay else { return }
                    self.beganPreroll = true
                    self.staging.preroll(atRate: 1) { _ in }
                }
            }
        }

        deinit {
            let id = cacheJob
            Task { @MainActor in AudioPlaybackCache.shared.leave(id, listened: 0, duration: 0) }
        }
        func takePlayer() -> AVPlayer {
            observation = nil
            staging.cancelPendingPrerolls()
            item.preferredForwardBufferDuration = 0
            staging.isMuted = false
            return staging
        }
    }
    @ObservationIgnored private let fetchDiscovery: () async throws -> ShuffleTrack
    private var isResolving = false
    private var isBuffering = false

    var isLoading: Bool { isResolving || isBuffering || isFetchingDiscovery }
    var isShuffled: Bool { queue.isShuffled }
    var queueModeBadgeSystemImage: String? {
        if isShuffled { return "shuffle" }
        return repeatMode == .off ? nil : repeatMode.systemImage
    }
    var canPlayNext: Bool { isDiscovery ? !isFetchingDiscovery : queue.canMove(by: 1, wraps: repeatMode == .all) }
    var canPlayPrevious: Bool { !isDiscovery || queue.currentIndex > 0 }

    /// 接下来要播放的曲目，按播放顺序。
    var upcoming: [UpcomingTrack] {
        if isDiscovery { return [] }
        return queue.upcomingIndices(wraps: repeatMode == .all).map { UpcomingTrack(index: $0, track: queue.tracks[$0]) }
    }

    @ObservationIgnored private var player: AVPlayer
    @ObservationIgnored private var standbyPlayer: AVPlayer
    @ObservationIgnored private var bypassCacheForRetry = false
    @ObservationIgnored private var cacheListenedAtEnd: TimeInterval = 0
    @ObservationIgnored private var audioCacheJob: UUID?
    @ObservationIgnored private let resolver: StreamResolver
    @ObservationIgnored private let persistence: PlaybackPersistence
    @ObservationIgnored private let nowPlaying: NowPlayingSession
    @ObservationIgnored private var observers: [NSObjectProtocol] = []
    @ObservationIgnored private var timeObserver: Any?
    @ObservationIgnored private var timeControlObservation: NSKeyValueObservation?
    @ObservationIgnored private var itemStatusObservation: NSKeyValueObservation?
    @ObservationIgnored private var loadTask: Task<Void, Never>?
    /// 每次换曲目加一，旧的异步回调据此作废。
    @ObservationIgnored private var loadGeneration = 0
    /// 加载完成后要跳到的位置（恢复上次进度、地址过期后接着播）。
    @ObservationIgnored private var pendingSeek: TimeInterval = 0
    /// 地址过期导致的失败只重试一次，避免无限重试。
    @ObservationIgnored private var retriedTrackID: String?
    @ObservationIgnored private var loadedLocalFile = false
    #if os(iOS)
    @ObservationIgnored private var resumeAfterInterruption = false
    #endif
    @ObservationIgnored private var isSeeking = false
    @ObservationIgnored private var lastSavedProgress: TimeInterval = 0
    /// `progress` 最近一次更新的时间，用来推算两次刷新之间的播放位置。
    @ObservationIgnored private var progressUpdatedAt = Date.now

    init(resolver: StreamResolver = StreamResolver(), persistence: PlaybackPersistence = PlaybackPersistence(),
         fetchDiscovery: @escaping () async throws -> ShuffleTrack = { try await DizzyCommunity.shared.shuffle() }) {
        self.fetchDiscovery = fetchDiscovery
        let player = AVPlayer()
        self.player = player
        let standbyPlayer = AVPlayer()
        self.standbyPlayer = standbyPlayer
        self.resolver = resolver
        self.persistence = persistence
        nowPlaying = NowPlayingSession(player: player, standbyPlayer: standbyPlayer)
        #if os(macOS)
        player.volume = min(max(volume, 0), 1)
        #endif
        installObservers()
        installRemoteCommands()
    }

    // MARK: - 播放控制

    /// 播放一组曲目。`streams` 是专辑页已经拿到的播放地址，可以省掉一次请求。
    func play(_ tracks: [Track], startAt index: Int, streams: [String: URL] = [:], sourceID: Int? = nil, heartMode: Bool = false) {
        guard !tracks.isEmpty else { return }
        isHeartMode = heartMode
        queueSourceID = sourceID
        cancelDiscoveryRequest()
        isDiscovery = false
        remoteDiscoveryID = nil
        if tracks.first?.remoteSource == nil, let discID = tracks.first?.discID {
            resolver.store(streams, for: discID)
        }
        queue.replace(with: tracks, startingAt: index)
        load(autoplay: true)
    }

    /// A discovery session keeps only track metadata; expiring stream URLs stay in the resolver.
    func playDiscovery(_ selection: ShuffleTrack, autoplay: Bool = true) {
        isHeartMode = false
        queueSourceID = nil
        cancelDiscoveryRequest()
        isDiscovery = true
        remoteDiscoveryID = nil
        queue.restore(tracks: [selection.track], currentIndex: 0, isShuffled: false, shuffledOrder: [])
        resolver.store([selection.track.number: selection.stream], for: selection.track.discID)
        load(autoplay: autoplay)
    }

    private func cancelDiscoveryRequest() {
        discoveryGeneration += 1
        discoveryPrefetch?.cancel()
        discoveryPrefetch = nil
        preparedDiscovery = nil
        standbyPlayer.cancelPendingPrerolls()
        standbyPlayer.replaceCurrentItem(with: nil)
        discoveryTask?.cancel()
        discoveryTask = nil
        isFetchingDiscovery = false
    }

    /// Coalesced between background preparation and the next button; never advance twice.
    private func prepareNextDiscovery() {
        guard isDiscovery, discoveryPrefetch == nil else { return }
        let generation = discoveryGeneration
        let remoteID = remoteDiscoveryID
        let remoteNext = remoteID.flatMap { remoteDiscoverySources[$0] }
        discoveryPrefetch = Task { [weak self, fetchDiscovery, resolver] in
            let track: Track
            if remoteID != nil {
                guard let remoteNext else { throw PlaybackError.unavailable }
                track = try await remoteNext()
            } else {
                let selection = try await fetchDiscovery()
                try Task.checkCancellation()
                guard self?.discoveryGeneration == generation else { throw CancellationError() }
                resolver.store([selection.track.number: selection.stream], for: selection.track.discID)
                track = selection.track
            }
            try Task.checkCancellation()
            guard self?.discoveryGeneration == generation else { throw CancellationError() }
            // Preparing another track must not release the current local file access.
            let url = try await resolver.stream(for: track, retainAccess: false)
            try Task.checkCancellation()
            guard self?.discoveryGeneration == generation else { throw CancellationError() }
            guard let self else { throw CancellationError() }
            let prepared = PreparedDiscovery(track: track, url: url, staging: self.standbyPlayer, resolver: resolver)
            self.preparedDiscovery = prepared
            return prepared
        }
    }

    private func requestNextDiscovery() {
        guard !isFetchingDiscovery else { return }
        prepareNextDiscovery()
        guard let prepared = discoveryPrefetch else { return }
        isFetchingDiscovery = true
        issue = nil
        let generation = discoveryGeneration
        discoveryTask = Task { [weak self] in
            do {
                let next = try await prepared.value
                try Task.checkCancellation()
                guard let self, self.isDiscovery, self.discoveryGeneration == generation else { return }
                self.discoveryPrefetch = nil
                self.preparedDiscovery = nil
                self.isFetchingDiscovery = false
                self.discoveryTask = nil
                var history = Array(self.queue.tracks.prefix(self.queue.currentIndex + 1))
                history.append(next.track)
                if history.count > 200 { history.removeFirst(history.count - 200) }
                self.queue.restore(tracks: history, currentIndex: history.count - 1, isShuffled: false, shuffledOrder: [])
                // A long pause may outlive the signed URL. In that case resolve again normally.
                let usable = self.resolver.isFresh(next.url, for: next.track) && next.item.status != .failed
                if !usable {
                    self.standbyPlayer.cancelPendingPrerolls()
                    self.standbyPlayer.replaceCurrentItem(with: nil)
                }
                self.load(autoplay: self.isPlaying, prepared: usable ? next : nil)
            } catch {
                guard let self, self.discoveryGeneration == generation else { return }
                self.discoveryPrefetch = nil
                self.preparedDiscovery = nil
                self.isFetchingDiscovery = false
                self.discoveryTask = nil
                if !(error is CancellationError) {
                    self.issue = "获取下一首失败：\(error.localizedDescription)。可以再次点击下一首重试。"
                }
            }
        }
    }

    /// 播放队列里的某一首（播放页的「继续播放」列表）。
    func playFromQueue(at index: Int) {
        guard queue.select(index: index) else { return }
        load(autoplay: true)
    }

    func moveUpcomingQueueItems(fromOffsets source: IndexSet, toOffset destination: Int) {
        guard !isDiscovery else { return }
        queue.moveUpcomingSongs(fromOffsets: source, toOffset: destination, wraps: repeatMode == .all)
        saveState()
    }

    /// 某一时刻的播放位置：进度每 0.5 秒刷新一次，中间按流逝的时间推算。动态背景用它驱动动画，
    /// 暂停时停住、继续播放时接着动。
    func estimatedProgress(at date: Date = .now) -> TimeInterval {
        guard isPlaying, !isLoading else { return progress }
        return progress + max(date.timeIntervalSince(progressUpdatedAt), 0)
    }

    /// 这首歌在播放缓存里时返回缓存的实际音质；换了账号或音质对不上就是 nil。
    func cachedQuality(for track: Track) -> String? {
        resolver.audioCacheKey(for: track).flatMap(AudioPlaybackCache.shared.cachedQuality)
    }

    func togglePlayback() {
        isPlaying ? pause() : resume()
    }

    func resume() {
        guard currentTrack != nil else { return }
        reporting.resumeIfNeeded(currentTrack, sourceID: queueSourceID)
        // 刚恢复的队列还没加载音频，或上次播放失败：重新获取地址。
        if player.currentItem == nil || issue != nil {
            load(autoplay: true, startAt: progress, continuing: true)
            return
        }
        isPlaying = true
        activateAndPlay()
        updateNowPlaying()
    }

    func pause() {
        reporting.setPlaying(false)
        isPlaying = false
        player.pause()
        updateNowPlaying()
        saveState()
    }

    func next() {
        if isDiscovery { requestNextDiscovery(); return }
        guard queue.move(by: 1, wraps: repeatMode == .all) else { return }
        load(autoplay: isPlaying)
    }

    /// 播放超过 3 秒时回到开头，否则回到上一首。
    func previous() {
        if isDiscovery {
            cancelDiscoveryRequest()
            guard queue.move(by: -1, wraps: false) else { return }
            load(autoplay: isPlaying)
            return
        }
        guard progress <= 3, queue.move(by: -1, wraps: repeatMode == .all) else {
            seek(to: 0)
            return
        }
        load(autoplay: isPlaying)
    }

    func seek(to seconds: TimeInterval) {
        let target = max(0, duration > 0 ? min(seconds, duration) : seconds)
        progress = target
        progressUpdatedAt = .now
        guard player.currentItem != nil else { return }
        isSeeking = true
        player.seek(
            to: CMTime(seconds: target, preferredTimescale: 600),
            toleranceBefore: .zero,
            toleranceAfter: .zero
        ) { [weak self] _ in
            guard let self else { return }
            Task { @MainActor in self.isSeeking = false }
        }
        updateNowPlaying()
    }

    func cycleRepeatMode() {
        guard !isDiscovery else { return }
        repeatMode = repeatMode.next
        saveState()
    }

    func toggleShuffle() {
        guard !isDiscovery else { return }
        queue.toggleShuffle()
        saveState()
    }

    // MARK: - 恢复与保存

    func remoteLyrics(for track: Track) async throws -> LocalLyrics? { try await resolver.lyrics(for: track) }

    func disableHeartMode() { isHeartMode = false; saveState() }

    /// Like MeloX, reload the active source at the same position and preserve
    /// play/pause intent. Prepared URLs are checked again before promotion.
    func remoteQualityDidChange(providerID: String) {
        resolver.invalidateRemote(providerID)
        if currentTrack?.remoteSource?.providerID == providerID {
            // Keep the next song's identity, but discard an in-flight old-quality transfer.
            AudioPlaybackCache.shared.leave(preparedDiscovery?.cacheJob, listened: 0, duration: 0)
            preparedDiscovery?.cacheJob = nil
            load(autoplay: isPlaying, startAt: estimatedProgress(), continuing: true)
        }
    }

    func remoteAccountDidChange(providerID: String) {
        resolver.invalidateRemote(providerID)
        if currentTrack?.remoteSource?.providerID == providerID {
            cancelDiscoveryRequest()
            load(autoplay: false, startAt: progress)
        }
    }

    /// 启动时恢复上次的队列和进度，保持暂停，点播放时才获取地址。
    func restore() {
        guard currentTrack == nil, let snapshot = persistence.load(), !snapshot.queue.isEmpty else { return }
        queue.restore(
            tracks: snapshot.queue,
            currentIndex: snapshot.currentIndex,
            isShuffled: snapshot.isShuffled,
            shuffledOrder: snapshot.shuffledOrder
        )
        isDiscovery = snapshot.isDiscovery == true
        remoteDiscoveryID = isDiscovery ? queue.currentTrack?.remoteSource?.providerID : nil
        queueSourceID = snapshot.sourceID
        isHeartMode = snapshot.heartMode == true
        repeatMode = snapshot.repeatMode
        currentTrack = queue.currentTrack
        if let currentTrack { reporting.begin(currentTrack, sourceID: queueSourceID) }
        progress = snapshot.progress
        lastSavedProgress = snapshot.progress
    }

    func saveState() {
        guard !queue.tracks.isEmpty else {
            persistence.clear()
            return
        }
        lastSavedProgress = progress
        persistence.save(PlaybackSnapshot(
            queue: queue.tracks,
            currentIndex: queue.currentIndex,
            progress: progress,
            repeatMode: repeatMode,
            isShuffled: queue.isShuffled,
            shuffledOrder: queue.persistedShuffleOrder,
            isDiscovery: isDiscovery,
            sourceID: queueSourceID,
            heartMode: isHeartMode
        ))
    }

    // MARK: - 加载

    private func load(autoplay: Bool, startAt position: TimeInterval = 0, preferLocal: Bool = true, prepared: PreparedDiscovery? = nil, continuing: Bool = false) {
        AudioPlaybackCache.shared.leave(audioCacheJob, listened: continuing ? 0 : max(cacheListenedAtEnd, reporting.listenedSeconds),
                                        duration: duration > 0 ? duration : currentTrack?.duration ?? 0)
        audioCacheJob = nil; cacheListenedAtEnd = 0
        AudioPlaybackCache.shared.protect(nil)
        loadTask?.cancel()
        guard let track = queue.currentTrack else { return }
        if !continuing { bypassCacheForRetry = false; reporting.begin(track, sourceID: queueSourceID) }
        else { reporting.setPlaying(false) }
        if let url = resolver.localURL(for: track), tagWritePaths.contains(LocalLibraryScanner.canonical(url)) {
            loadGeneration += 1
            player.pause()
            itemStatusObservation = nil
            player.replaceCurrentItem(with: nil)
            loadedFileURL = nil
            resolver.releaseLocalAccess()
            currentTrack = track
            isPlaying = false
            isResolving = false
            isBuffering = false
            progress = position
            issue = "此曲目正在保存标签，请稍后播放。"
            updateNowPlaying()
            return
        }
        if retriedTrackID != track.id {
            retriedTrackID = nil
        }
        loadGeneration += 1
        let generation = loadGeneration

        currentTrack = track
        issue = nil
        isPlaying = autoplay
        progress = position
        progressUpdatedAt = .now
        pendingSeek = position
        duration = 0
        isPreview = false
        loadedLocalFile = false
        isResolving = true
        itemStatusObservation = nil
        player.replaceCurrentItem(with: nil)
        loadedFileURL = nil
        nowPlaying.setTrack(
            track,
            duration: track.duration ?? 0,
            queueIndex: queue.position,
            queueCount: queue.tracks.count
        )
        saveState()

        if let prepared {
            audioCacheJob = prepared.cacheJob; prepared.cacheJob = nil
            start(url: prepared.url, generation: generation, preparedPlayer: prepared.takePlayer())
            prepareNextDiscovery()
            return
        }
        loadTask = Task { [weak self, resolver] in
            do {
                let url = try await resolver.stream(for: track, preferLocal: preferLocal)
                try Task.checkCancellation()
                self?.start(url: url, generation: generation)
                self?.prepareNextDiscovery()
            } catch is CancellationError {
            } catch {
                self?.fail(with: error.localizedDescription, generation: generation)
            }
        }
    }

    private func start(url: URL, generation: Int, preparedPlayer: AVPlayer? = nil) {
        guard generation == loadGeneration else { return }
        if url.isFileURL, tagWritePaths.contains(LocalLibraryScanner.canonical(url)) {
            fail(with: "此曲目正在保存标签，请稍后播放。", generation: generation)
            return
        }
        loadedFileURL = url.isFileURL ? url : nil
        isResolving = false
        loadedLocalFile = url.isFileURL
        isPreview = resolver.isPreview(for: currentTrack, url: url)
        if let preparedPlayer {
            player.pause()
            if let timeObserver { player.removeTimeObserver(timeObserver) }
            timeObserver = nil
            timeControlObservation = nil
            standbyPlayer = player
            player = preparedPlayer
            #if os(macOS)
            player.volume = min(max(volume, 0), 1)
            #endif
            installPlayerObservers()
        }
        AudioPlaybackCache.shared.protect(url.isFileURL ? url : nil)
        let item: AVPlayerItem
        if let existing = preparedPlayer?.currentItem { item = existing }
        else if !bypassCacheForRetry, !url.isFileURL, !isPreview, let track = currentTrack,
                let key = resolver.audioCacheKey(for: track), let actual = resolver.actualQuality(for: track),
                let cached = AudioPlaybackCache.shared.makeItem(url: url, key: key, actualQuality: actual) {
            item = cached.0; audioCacheJob = cached.1
        } else { item = AVPlayerItem(url: url) }
        itemStatusObservation = item.observe(\.status, options: [.new]) { [weak self] _, _ in
            guard let self else { return }
            Task { @MainActor in self.handleItemStatusChange(generation: generation) }
        }
        if preparedPlayer == nil { player.replaceCurrentItem(with: item) }
        handleItemStatusChange(generation: generation)
        if isPlaying {
            activateAndPlay()
        }
    }

    private func fail(with message: String, generation: Int) {
        guard generation == loadGeneration else { return }
        reporting.setPlaying(false)
        debugLog("播放失败：\(message)")
        isResolving = false
        isPlaying = false
        issue = message
        player.pause()
        updateNowPlaying()
    }

    private func activateAndPlay() {
        #if os(iOS)
        do {
            try AudioSessionConfigurator.activate()
            nowPlaying.activate()
        } catch {
            debugLog("激活音频会话失败：\(error)")
        }
        #else
        nowPlaying.activate()
        #endif
        player.play()
    }

    // MARK: - 播放器事件

    private func installPlayerObservers() {
        timeObserver = player.addPeriodicTimeObserver(
            forInterval: CMTime(seconds: 0.5, preferredTimescale: 600),
            queue: .main
        ) { [weak self, weak observedPlayer = player] time in
            MainActor.assumeIsolated {
                guard let self, self.player === observedPlayer else { return }
                self.handleTick(time.seconds)
            }
        }
        timeControlObservation = player.observe(\.timeControlStatus, options: [.initial, .new]) { [weak self, weak observedPlayer = player] _, _ in
            Task { @MainActor [weak self, weak observedPlayer] in
                guard let self, self.player === observedPlayer else { return }
                self.handleTimeControlStatusChange()
            }
        }

    }

    private func installObservers() {
        installPlayerObservers()
        let center = NotificationCenter.default
        observers.append(center.addObserver(forName: AVPlayerItem.didPlayToEndTimeNotification, object: nil, queue: .main) { [weak self] notification in
            MainActor.assumeIsolated {
                self?.handleItemEnded(notification.object)
            }
        })
        observers.append(center.addObserver(forName: AVPlayerItem.failedToPlayToEndTimeNotification, object: nil, queue: .main) { [weak self] notification in
            MainActor.assumeIsolated {
                guard let self, (notification.object as AnyObject?) === self.player.currentItem else { return }
                self.handleFailure()
            }
        })
        observers.append(center.addObserver(forName: .dizzyAccountDidChange, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated {
                if self?.remoteDiscoveryID == nil { self?.cancelDiscoveryRequest() }
                self?.resolver.clearDizzyLabCache()
            }
        })
        observers.append(center.addObserver(forName: .dizzyPurchaseDidComplete, object: nil, queue: .main) { [weak self] notification in
            MainActor.assumeIsolated {
                guard let self, let discID = notification.object as? String else { return }
                self.resolver.invalidate(discID: discID)
                if self.isDiscovery, self.remoteDiscoveryID == nil {
                    self.cancelDiscoveryRequest()
                    self.prepareNextDiscovery()
                }
                // 已加载的试听 AVPlayerItem 也需要换成完整版，保留用户的暂停状态与进度。
                if self.currentTrack?.remoteSource == nil, self.currentTrack?.discID == discID, self.isPreview || self.isResolving {
                    self.load(autoplay: self.isPlaying, startAt: self.progress)
                }
            }
        })
        #if os(iOS)
        // 文档没有说明这两个通知的 object 是什么，不按 object 过滤。
        observers.append(center.addObserver(forName: AVAudioSession.didBecomeInactiveNotification, object: nil, queue: .main) { [weak self] notification in
            MainActor.assumeIsolated {
                self?.handleSessionDeactivated(notification)
            }
        })
        observers.append(center.addObserver(forName: AVAudioSession.resumptionRecommendationNotification, object: nil, queue: .main) { [weak self] notification in
            MainActor.assumeIsolated {
                self?.handleResumptionRecommendation(notification)
            }
        })
        #endif
    }

    private func installRemoteCommands() {
        nowPlaying.onPlay = { [weak self] in self?.resume() }
        nowPlaying.onPause = { [weak self] in self?.pause() }
        nowPlaying.onNext = { [weak self] in self?.next() }
        nowPlaying.onPrevious = { [weak self] in self?.previous() }
        nowPlaying.onSeek = { [weak self] position in self?.seek(to: position) }
    }

    private func handleTick(_ seconds: Double) {
        guard !isSeeking, !isResolving, seconds.isFinite, player.currentItem != nil else { return }
        reporting.setPlaying(isPlaying && player.timeControlStatus == .playing)
        progress = max(seconds, 0)
        progressUpdatedAt = .now
        updateNowPlaying()
        if abs(progress - lastSavedProgress) >= 10 {
            saveState()
        }
    }

    private func handleTimeControlStatusChange() {
        reporting.setPlaying(isPlaying && !isResolving && player.timeControlStatus == .playing)
        // 切歌时会短暂处于「没有可播放的项目」，那段时间由 isResolving 表示，不算缓冲。
        let buffering = player.timeControlStatus == .waitingToPlayAtSpecifiedRate
            && player.reasonForWaitingToPlay != .noItemToPlay
        if buffering != isBuffering {
            debugLog("缓冲 \(buffering ? "开始" : "结束")：\(player.reasonForWaitingToPlay?.rawValue ?? "")")
        }
        isBuffering = buffering
    }

    private func handleItemStatusChange(generation: Int) {
        guard generation == loadGeneration, let item = player.currentItem else { return }
        switch item.status {
        case .readyToPlay:
            let seconds = item.duration.seconds
            if seconds.isFinite, seconds > 0 {
                duration = seconds
            }
            // 恢复的进度可能超过试听片段的长度，这时从头播放。
            if pendingSeek > 0 {
                let target = duration > 0 && pendingSeek >= duration - 1 ? 0 : pendingSeek
                pendingSeek = 0
                seek(to: target)
            }
            updateNowPlaying()
        case .failed:
            handleFailure()
        default:
            break
        }
    }

    private func handleItemEnded(_ object: Any?) {
        guard (object as AnyObject?) === player.currentItem else { return }
        cacheListenedAtEnd = max(cacheListenedAtEnd, reporting.listenedSeconds)
        reporting.finish()
        if isDiscovery {
            if remoteDiscoveryID != nil {
                isPlaying = true
                requestNextDiscovery()
                return
            }
            isPlaying = false
            player.pause()
            seek(to: 0)
            saveState()
            return
        }
        switch repeatMode {
        case .one:
            if let currentTrack { reporting.begin(currentTrack, sourceID: queueSourceID) }
            seek(to: 0)
            player.play()
        case .all, .off:
            if queue.move(by: 1, wraps: repeatMode == .all) {
                load(autoplay: true)
            } else {
                // 整个队列播完：停在最后一首的开头。
                isPlaying = false
                player.pause()
                seek(to: 0)
                saveState()
            }
        }
    }

    /// 播放出错多半是地址过期（403）：丢掉缓存重新获取一次，从当前位置接着播。
    private func handleFailure() {
        guard let track = currentTrack else { return }
        if retriedTrackID != track.id {
            retriedTrackID = track.id
            if audioCacheJob != nil {
                bypassCacheForRetry = true
                AudioPlaybackCache.shared.discard(audioCacheJob)
            }
            if loadedLocalFile || audioCacheJob != nil, let key = resolver.audioCacheKey(for: track) { AudioPlaybackCache.shared.remove(key) }
            resolver.invalidate(for: track)
            // 本地文件可能被外部移走或损坏，只回退一次到串流，避免不断加载同一坏文件。
            load(autoplay: isPlaying, startAt: progress, preferLocal: !loadedLocalFile, continuing: true)
        } else {
            fail(with: PlaybackError.failed.localizedDescription, generation: loadGeneration)
        }
    }

    #if os(iOS)
    /// 来电、其他 App 播放、耳机断开等，系统停用了音频会话，AVPlayer 已经自己暂停。
    private func handleSessionDeactivated(_ notification: Notification) {
        let context = notification.userInfo?[AVAudioSession.deactivationContextKey] as? AVAudioSession.DeactivationContext
        debugLog("音频会话停用：source=\(context?.source.rawValue ?? -1) reason=\(context?.interruptionContext?.reason.rawValue ?? 999) isPlaying=\(isPlaying)")
        guard context?.source != .app else { return }
        // 耳机断开后不自动恢复；来电等中断结束后按系统建议接着播。
        reporting.setPlaying(false)
        resumeAfterInterruption = isPlaying && context?.interruptionContext?.reason != .routeDisconnected
        isPlaying = false
        updateNowPlaying()
        saveState()
    }

    private func handleResumptionRecommendation(_ notification: Notification) {
        let context = notification.userInfo?[AVAudioSession.resumptionContextKey] as? AVAudioSession.ResumptionContext
        debugLog("系统恢复建议：recommendation=\(context?.recommendation.rawValue ?? -1) resumeAfterInterruption=\(resumeAfterInterruption)")
        if resumeAfterInterruption, context?.recommendation == .shouldResume {
            resume()
        }
        resumeAfterInterruption = false
    }
    #endif

    private func updateNowPlaying() {
        nowPlaying.updatePlayback(
            position: progress,
            duration: duration > 0 ? duration : currentTrack?.duration ?? 0,
            isPlaying: isPlaying
        )
    }
}

/// 「继续播放」里的一首。同一首曲目可能在队列里出现多次，所以用队列下标区分。
nonisolated struct UpcomingTrack: Identifiable, Sendable {
    /// 在队列里的下标，用于点播。
    let index: Int
    let track: Track

    var id: Int { index }
}
