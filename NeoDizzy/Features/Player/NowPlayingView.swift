import SwiftUI

/// 播放页：大封面、曲目信息、进度条和播放控制。布局参考 MeloX 的播放页，
/// 不含歌词、AutoMix 和动态背景。
struct NowPlayingView: View {
    @Environment(PlayerStore.self) private var player
    @Environment(\.dismiss) private var dismiss
    @Environment(\.accessibilityReduceMotion) private var accessibilityReduceMotion

    var body: some View {
        ZStack {
            if let track = player.currentTrack {
                backdrop(track)
                VStack(spacing: 28) {
                    Spacer(minLength: 8)
                    ArtworkImage(url: track.coverURL, cornerRadius: 18)
                        .frame(maxWidth: 340)
                        .shadow(color: .black.opacity(0.45), radius: 24, y: 12)
                        .scaleEffect(player.isPlaying ? 1 : 0.86)
                        .animation(accessibilityReduceMotion ? nil : .spring(duration: 0.45, bounce: 0.25), value: player.isPlaying)
                    info(track)
                    NowPlayingProgress()
                    controls
                    footer(track)
                    Spacer(minLength: 8)
                }
                .padding(.horizontal, 28)
            }
        }
        .presentationDragIndicator(.visible)
        .preferredColorScheme(.dark)
        .onChange(of: player.currentTrack == nil) { _, isEmpty in
            if isEmpty { dismiss() }
        }
    }

    private func backdrop(_ track: Track) -> some View {
        GeometryReader { proxy in
            // 封面是正方形，按屏幕长边放大，盖满整个背景。
            let side = max(proxy.size.width, proxy.size.height)
            ArtworkImage(url: track.coverURL, cornerRadius: 0)
                .frame(width: side, height: side)
                .position(x: proxy.size.width / 2, y: proxy.size.height / 2)
                .blur(radius: 60)
                .opacity(0.45)
        }
        .background(DizzyPalette.background)
        .ignoresSafeArea()
    }

    private func info(_ track: Track) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(track.title)
                    .font(.title3.bold())
                    .foregroundStyle(DizzyPalette.text)
                    .lineLimit(2)
                if player.isPreview {
                    Text("试听")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(DizzyPalette.background)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(DizzyPalette.accent, in: .capsule)
                }
            }
            Text(track.artists)
                .font(.body)
                .foregroundStyle(DizzyPalette.text.opacity(0.75))
                .lineLimit(1)
            Text(track.albumTitle)
                .font(.subheadline)
                .foregroundStyle(DizzyPalette.mutedText)
                .lineLimit(1)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var controls: some View {
        HStack {
            Button {
                player.toggleShuffle()
            } label: {
                Image(systemName: "shuffle")
                    .font(.title3)
                    .foregroundStyle(player.isShuffled ? DizzyPalette.accent : DizzyPalette.mutedText)
            }
            .accessibilityLabel("随机播放")
            .accessibilityValue(player.isShuffled ? "开" : "关")

            Spacer()

            Button {
                player.previous()
            } label: {
                Image(systemName: "backward.fill")
                    .font(.title)
            }
            .accessibilityLabel("上一首")

            Spacer()

            Button {
                player.togglePlayback()
            } label: {
                ZStack {
                    if player.isLoading {
                        ProgressView()
                            .controlSize(.large)
                    } else {
                        Image(systemName: player.isPlaying ? "pause.fill" : "play.fill")
                            .font(.system(size: 44))
                            .contentTransition(accessibilityReduceMotion ? .identity : .symbolEffect(.replace))
                    }
                }
                .frame(width: 72, height: 72)
                .contentShape(.circle)
            }
            .accessibilityLabel(player.isPlaying ? "暂停" : "播放")

            Spacer()

            Button {
                player.next()
            } label: {
                Image(systemName: "forward.fill")
                    .font(.title)
            }
            .disabled(!player.canPlayNext)
            .accessibilityLabel("下一首")

            Spacer()

            Button {
                player.cycleRepeatMode()
            } label: {
                Image(systemName: player.repeatMode.systemImage)
                    .font(.title3)
                    .foregroundStyle(player.repeatMode == .off ? DizzyPalette.mutedText : DizzyPalette.accent)
            }
            .accessibilityLabel(player.repeatMode.accessibilityTitle)
        }
        .buttonStyle(.plain)
        .foregroundStyle(DizzyPalette.text)
    }

    @ViewBuilder
    private func footer(_ track: Track) -> some View {
        if let issue = player.issue {
            VStack(spacing: 8) {
                Text(issue)
                    .font(.footnote)
                    .foregroundStyle(DizzyPalette.danger)
                Button("重试") { player.resume() }
                    .buttonStyle(.bordered)
            }
        } else if player.isPreview {
            VStack(spacing: 6) {
                Text("正在试听片段。购买后可以收听完整版。")
                    .font(.footnote)
                    .foregroundStyle(DizzyPalette.mutedText)
                Link("在网页中购买", destination: DizzyURL.disc(track.discID))
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(DizzyPalette.accent)
            }
            .multilineTextAlignment(.center)
        }
    }
}

/// 进度条：按住后跟随手指，松手才跳转，避免拖动过程中反复请求音频；点一下也能直接跳到那里。
/// 不用系统 Slider：它在播放页里拖动后没有跳转，也不支持点按。
private struct NowPlayingProgress: View {
    @Environment(PlayerStore.self) private var player
    @Environment(\.accessibilityReduceMotion) private var accessibilityReduceMotion
    @State private var scrubbingPosition: TimeInterval?

    var body: some View {
        let duration = player.duration
        let position = scrubbingPosition ?? min(player.progress, duration)
        let fraction = duration > 0 ? min(max(position / duration, 0), 1) : 0
        let isScrubbing = scrubbingPosition != nil

        VStack(spacing: 6) {
            GeometryReader { proxy in
                ZStack(alignment: .leading) {
                    Capsule()
                        .fill(DizzyPalette.text.opacity(0.2))
                    Capsule()
                        .fill(DizzyPalette.accent)
                        .frame(width: proxy.size.width * fraction)
                }
                .frame(height: isScrubbing ? 12 : 6)
                .frame(maxHeight: .infinity)
                .contentShape(.rect)
                .gesture(scrubGesture(width: proxy.size.width, duration: duration))
            }
            .frame(height: 28)
            .animation(accessibilityReduceMotion ? nil : .snappy(duration: 0.2), value: isScrubbing)

            HStack {
                Text(Self.format(position))
                Spacer()
                Text(duration > 0 ? "-" + Self.format(max(duration - position, 0)) : "--:--")
            }
            .font(.caption.monospacedDigit())
            .foregroundStyle(isScrubbing ? DizzyPalette.text : DizzyPalette.mutedText)
        }
        .onChange(of: player.currentTrack?.id) {
            // 不把上一首的拖动带到下一首。
            scrubbingPosition = nil
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("播放进度")
        .accessibilityValue(duration > 0 ? "\(Self.format(position))，共 \(Self.format(duration))" : "")
        .accessibilityAdjustableAction { direction in
            switch direction {
            case .increment: player.seek(to: player.progress + 10)
            case .decrement: player.seek(to: player.progress - 10)
            @unknown default: break
            }
        }
    }

    private func scrubGesture(width: CGFloat, duration: TimeInterval) -> some Gesture {
        func position(at x: CGFloat) -> TimeInterval {
            min(max(x / max(width, 1), 0), 1) * duration
        }
        return DragGesture(minimumDistance: 0)
            .onChanged { value in
                guard duration > 0 else { return }
                scrubbingPosition = position(at: value.location.x)
            }
            .onEnded { value in
                guard duration > 0 else { return }
                player.seek(to: position(at: value.location.x))
                scrubbingPosition = nil
            }
    }

    private static func format(_ seconds: TimeInterval) -> String {
        Duration.seconds(seconds.rounded(.down)).formatted(.time(pattern: .minuteSecond))
    }
}
