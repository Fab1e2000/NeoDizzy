import AVFoundation
import Foundation

/// 播放器：单个 AVPlayer 加一个播放队列。迷你播放器、播放页和系统媒体控制共用这一份状态。
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
    private var queue = PlaybackQueue()
    private var isResolving = false
    private var isBuffering = false

    var isLoading: Bool { isResolving || isBuffering }
    var isShuffled: Bool { queue.isShuffled }
    var canPlayNext: Bool { queue.canMove(by: 1, wraps: repeatMode == .all) }

    /// 接下来要播放的曲目，按播放顺序。
    var upcoming: [UpcomingTrack] {
        queue.upcomingIndices(wraps: repeatMode == .all).map { UpcomingTrack(index: $0, track: queue.tracks[$0]) }
    }

    @ObservationIgnored private let player: AVPlayer
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
    @ObservationIgnored private var resumeAfterInterruption = false
    @ObservationIgnored private var isSeeking = false
    @ObservationIgnored private var lastSavedProgress: TimeInterval = 0
    /// `progress` 最近一次更新的时间，用来推算两次刷新之间的播放位置。
    @ObservationIgnored private var progressUpdatedAt = Date.now

    init(resolver: StreamResolver = StreamResolver(), persistence: PlaybackPersistence = PlaybackPersistence()) {
        let player = AVPlayer()
        self.player = player
        self.resolver = resolver
        self.persistence = persistence
        nowPlaying = NowPlayingSession(player: player)
        installObservers()
        installRemoteCommands()
    }

    // MARK: - 播放控制

    /// 播放一组曲目。`streams` 是专辑页已经拿到的播放地址，可以省掉一次请求。
    func play(_ tracks: [Track], startAt index: Int, streams: [String: URL] = [:]) {
        guard !tracks.isEmpty else { return }
        if let discID = tracks.first?.discID {
            resolver.store(streams, for: discID)
        }
        queue.replace(with: tracks, startingAt: index)
        load(autoplay: true)
    }

    /// 播放队列里的某一首（播放页的「继续播放」列表）。
    func playFromQueue(at index: Int) {
        guard queue.select(index: index) else { return }
        load(autoplay: true)
    }

    /// 某一时刻的播放位置：进度每 0.5 秒刷新一次，中间按流逝的时间推算。动态背景用它驱动动画，
    /// 暂停时停住、继续播放时接着动。
    func estimatedProgress(at date: Date = .now) -> TimeInterval {
        guard isPlaying, !isLoading else { return progress }
        return progress + max(date.timeIntervalSince(progressUpdatedAt), 0)
    }

    func togglePlayback() {
        isPlaying ? pause() : resume()
    }

    func resume() {
        guard currentTrack != nil else { return }
        // 刚恢复的队列还没加载音频，或上次播放失败：重新获取地址。
        if player.currentItem == nil || issue != nil {
            load(autoplay: true, startAt: progress)
            return
        }
        isPlaying = true
        activateAndPlay()
        updateNowPlaying()
    }

    func pause() {
        isPlaying = false
        player.pause()
        updateNowPlaying()
        saveState()
    }

    func next() {
        guard queue.move(by: 1, wraps: repeatMode == .all) else { return }
        load(autoplay: isPlaying)
    }

    /// 播放超过 3 秒时回到开头，否则回到上一首。
    func previous() {
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
        repeatMode = repeatMode.next
        saveState()
    }

    func toggleShuffle() {
        queue.toggleShuffle()
        saveState()
    }

    // MARK: - 恢复与保存

    /// 启动时恢复上次的队列和进度，保持暂停，点播放时才获取地址。
    func restore() {
        guard currentTrack == nil, let snapshot = persistence.load(), !snapshot.queue.isEmpty else { return }
        queue.restore(
            tracks: snapshot.queue,
            currentIndex: snapshot.currentIndex,
            isShuffled: snapshot.isShuffled,
            shuffledOrder: snapshot.shuffledOrder
        )
        repeatMode = snapshot.repeatMode
        currentTrack = queue.currentTrack
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
            shuffledOrder: queue.persistedShuffleOrder
        ))
    }

    // MARK: - 加载

    private func load(autoplay: Bool, startAt position: TimeInterval = 0) {
        loadTask?.cancel()
        guard let track = queue.currentTrack else { return }
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
        isResolving = true
        itemStatusObservation = nil
        player.replaceCurrentItem(with: nil)
        nowPlaying.setTrack(
            track,
            duration: track.duration ?? 0,
            queueIndex: queue.position,
            queueCount: queue.tracks.count
        )
        saveState()

        loadTask = Task { [weak self, resolver] in
            do {
                let url = try await resolver.stream(for: track)
                try Task.checkCancellation()
                self?.start(url: url, generation: generation)
            } catch is CancellationError {
            } catch {
                self?.fail(with: error.localizedDescription, generation: generation)
            }
        }
    }

    private func start(url: URL, generation: Int) {
        guard generation == loadGeneration else { return }
        isResolving = false
        isPreview = DizzyURL.isPreviewStream(url)
        let item = AVPlayerItem(url: url)
        itemStatusObservation = item.observe(\.status, options: [.new]) { [weak self] _, _ in
            guard let self else { return }
            Task { @MainActor in self.handleItemStatusChange(generation: generation) }
        }
        player.replaceCurrentItem(with: item)
        if isPlaying {
            activateAndPlay()
        }
    }

    private func fail(with message: String, generation: Int) {
        guard generation == loadGeneration else { return }
        debugLog("播放失败：\(message)")
        isResolving = false
        isPlaying = false
        issue = message
        player.pause()
        updateNowPlaying()
    }

    private func activateAndPlay() {
        do {
            try AudioSessionConfigurator.activate()
        } catch {
            debugLog("激活音频会话失败：\(error)")
        }
        player.play()
    }

    // MARK: - 播放器事件

    private func installObservers() {
        timeObserver = player.addPeriodicTimeObserver(
            forInterval: CMTime(seconds: 0.5, preferredTimescale: 600),
            queue: .main
        ) { [weak self] time in
            MainActor.assumeIsolated {
                self?.handleTick(time.seconds)
            }
        }
        timeControlObservation = player.observe(\.timeControlStatus, options: [.initial, .new]) { [weak self] _, _ in
            guard let self else { return }
            Task { @MainActor in self.handleTimeControlStatusChange() }
        }

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
                self?.resolver.removeAll()
            }
        })
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
        progress = max(seconds, 0)
        progressUpdatedAt = .now
        updateNowPlaying()
        if abs(progress - lastSavedProgress) >= 10 {
            saveState()
        }
    }

    private func handleTimeControlStatusChange() {
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
        switch repeatMode {
        case .one:
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
            resolver.invalidate(discID: track.discID)
            load(autoplay: isPlaying, startAt: progress)
        } else {
            fail(with: PlaybackError.failed.localizedDescription, generation: loadGeneration)
        }
    }

    /// 来电、其他 App 播放、耳机断开等，系统停用了音频会话，AVPlayer 已经自己暂停。
    private func handleSessionDeactivated(_ notification: Notification) {
        let context = notification.userInfo?[AVAudioSession.deactivationContextKey] as? AVAudioSession.DeactivationContext
        debugLog("音频会话停用：source=\(context?.source.rawValue ?? -1) reason=\(context?.interruptionContext?.reason.rawValue ?? 999) isPlaying=\(isPlaying)")
        guard context?.source != .app else { return }
        // 耳机断开后不自动恢复；来电等中断结束后按系统建议接着播。
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
