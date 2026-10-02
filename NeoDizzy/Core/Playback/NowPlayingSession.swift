// 移植自 MeloX（GPLv3）Core/Playback/Session/NowPlayingSession.swift：
// 去掉歌词和播客，标识改为 DizzyLab 的专辑 / 曲目，封面改用 Nuke 加载。

import AVFoundation
import MediaPlayer
import Nuke
import UIKit

/// 锁屏、控制中心和耳机线控。
final class NowPlayingSession: NSObject, MPNowPlayingSessionDelegate {
    var onPlay: (() -> Void)?
    var onPause: (() -> Void)?
    var onNext: (() -> Void)?
    var onPrevious: (() -> Void)?
    var onSeek: ((TimeInterval) -> Void)?

    private let playbackSession: MPNowPlayingSession
    private var commandTargets: [(MPRemoteCommand, Any)] = []
    private var nowPlayingInfo: [String: Any] = [:]
    private var artworkTask: Task<Void, Never>?
    private var representedTrackID: String?
    private var wantsActiveSession = false
    private var activationPending = false

    private var nowPlayingCenter: MPNowPlayingInfoCenter {
        playbackSession.nowPlayingInfoCenter
    }

    private var commandCenter: MPRemoteCommandCenter {
        playbackSession.remoteCommandCenter
    }

    init(player: AVPlayer) {
        playbackSession = MPNowPlayingSession(players: [player])
        playbackSession.automaticallyPublishesNowPlayingInfo = false
        super.init()
        playbackSession.delegate = self
        installRemoteCommands()
    }

    deinit {
        artworkTask?.cancel()
        for (command, target) in commandTargets {
            command.removeTarget(target)
        }
    }

    func setTrack(_ track: Track, duration: TimeInterval, queueIndex: Int, queueCount: Int) {
        representedTrackID = track.id
        artworkTask?.cancel()
        nowPlayingInfo = [
            MPMediaItemPropertyTitle: track.title,
            MPMediaItemPropertyArtist: track.artists,
            MPMediaItemPropertyAlbumTitle: track.albumTitle,
            MPMediaItemPropertyPlaybackDuration: max(duration, 0),
            MPNowPlayingInfoPropertyMediaType: MPNowPlayingInfoMediaType.audio.rawValue,
            MPNowPlayingInfoPropertyIsLiveStream: false,
            MPNowPlayingInfoPropertyExternalContentIdentifier: track.localSource.map { "neodizzy:local-track:\($0.trackID)" } ?? "dizzylab:track:\(track.id)",
            MPNowPlayingInfoCollectionIdentifier: track.localSource.map { "neodizzy:local-album:\($0.albumID)" } ?? "dizzylab:disc:\(track.discID)",
            MPNowPlayingInfoPropertyPlaybackQueueIndex: max(queueIndex, 0),
            MPNowPlayingInfoPropertyPlaybackQueueCount: max(queueCount, 1),
        ]
        nowPlayingCenter.nowPlayingInfo = nowPlayingInfo
        loadArtwork(from: track.coverURL, trackID: track.id)
    }

    func updatePlayback(position: TimeInterval, duration: TimeInterval, isPlaying: Bool) {
        guard representedTrackID != nil else { return }
        nowPlayingInfo[MPMediaItemPropertyPlaybackDuration] = max(duration, 0)
        nowPlayingInfo[MPNowPlayingInfoPropertyElapsedPlaybackTime] = max(position, 0)
        nowPlayingInfo[MPNowPlayingInfoPropertyPlaybackRate] = isPlaying ? 1.0 : 0.0
        nowPlayingInfo[MPNowPlayingInfoPropertyDefaultPlaybackRate] = 1.0
        nowPlayingCenter.nowPlayingInfo = nowPlayingInfo
        nowPlayingCenter.playbackState = isPlaying ? .playing : .paused
        commandCenter.playCommand.isEnabled = !isPlaying
        commandCenter.pauseCommand.isEnabled = isPlaying
    }

    /// Called only after AVAudioSession is active and the player owns its item.
    func activate() {
        wantsActiveSession = true
        requestActivation()
    }

    private func requestActivation() {
        guard wantsActiveSession, representedTrackID != nil,
              !playbackSession.isActive, playbackSession.canBecomeActive, !activationPending else { return }
        activationPending = true
        playbackSession.becomeActiveIfPossible { [weak self] active in
            Task { @MainActor [weak self] in
                guard let self else { return }
                self.activationPending = false
                if active { self.nowPlayingCenter.nowPlayingInfo = self.nowPlayingInfo }
            }
        }
    }

    nonisolated func nowPlayingSessionDidChangeCanBecomeActive(_ nowPlayingSession: MPNowPlayingSession) {
        Task { @MainActor [weak self] in self?.requestActivation() }
    }

    func clear() {
        wantsActiveSession = false
        representedTrackID = nil
        artworkTask?.cancel()
        artworkTask = nil
        nowPlayingInfo = [:]
        nowPlayingCenter.nowPlayingInfo = nil
        nowPlayingCenter.playbackState = .stopped
    }

    private func installRemoteCommands() {
        commandCenter.playCommand.isEnabled = true
        commandCenter.pauseCommand.isEnabled = false
        commandCenter.togglePlayPauseCommand.isEnabled = false
        commandCenter.nextTrackCommand.isEnabled = true
        commandCenter.previousTrackCommand.isEnabled = true
        commandCenter.changePlaybackPositionCommand.isEnabled = true
        commandCenter.stopCommand.isEnabled = false
        commandCenter.skipForwardCommand.isEnabled = false
        commandCenter.skipBackwardCommand.isEnabled = false
        commandCenter.seekForwardCommand.isEnabled = false
        commandCenter.seekBackwardCommand.isEnabled = false
        commandCenter.changePlaybackRateCommand.isEnabled = false
        commandCenter.changeRepeatModeCommand.isEnabled = false
        commandCenter.changeShuffleModeCommand.isEnabled = false

        addTarget(to: commandCenter.playCommand) { [weak self] _ in
            Task { @MainActor in self?.onPlay?() }
            return .success
        }
        addTarget(to: commandCenter.pauseCommand) { [weak self] _ in
            Task { @MainActor in self?.onPause?() }
            return .success
        }
        addTarget(to: commandCenter.nextTrackCommand) { [weak self] _ in
            Task { @MainActor in self?.onNext?() }
            return .success
        }
        addTarget(to: commandCenter.previousTrackCommand) { [weak self] _ in
            Task { @MainActor in self?.onPrevious?() }
            return .success
        }
        addTarget(to: commandCenter.changePlaybackPositionCommand) { [weak self] event in
            guard let event = event as? MPChangePlaybackPositionCommandEvent else {
                return .commandFailed
            }
            let position = event.positionTime
            Task { @MainActor in self?.onSeek?(position) }
            return .success
        }
    }

    private func addTarget(
        to command: MPRemoteCommand,
        handler: @escaping (MPRemoteCommandEvent) -> MPRemoteCommandHandlerStatus
    ) {
        let target = command.addTarget(handler: handler)
        commandTargets.append((command, target))
    }

    private func loadArtwork(from url: URL?, trackID: String) {
        guard let url else { return }
        artworkTask = Task { [weak self] in
            let request = ImageRequest(url: url, processors: [.resize(width: 1_024)])
            guard let image = try? await ImagePipeline.shared.image(for: request),
                  !Task.isCancelled,
                  let self,
                  self.representedTrackID == trackID else { return }
            self.nowPlayingInfo[MPMediaItemPropertyArtwork] = Self.artwork(for: image)
            self.nowPlayingCenter.nowPlayingInfo = self.nowPlayingInfo
        }
    }

    /// 系统在后台线程向 MPMediaItemArtwork 要图，闭包不能继承 MainActor 隔离。
    nonisolated private static func artwork(for image: UIImage) -> MPMediaItemArtwork {
        MPMediaItemArtwork(boundsSize: image.size) { _ in image }
    }
}
