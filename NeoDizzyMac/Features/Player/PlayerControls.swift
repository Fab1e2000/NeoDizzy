import AVKit
import SwiftUI

/// 播放控件的配色：普通界面用系统前景色；需要时可在深色背景上固定为白色。
enum PlayerControlTone {
    case standard, onDark

    var primary: Color { self == .onDark ? .white : .primary }
    var secondary: Color { self == .onDark ? .white.opacity(0.6) : .secondary }
    var track: Color { self == .onDark ? .white.opacity(0.22) : .primary.opacity(0.14) }
    var fill: Color { self == .onDark ? .white.opacity(0.85) : .primary.opacity(0.55) }
}

/// 播放条按钮：悬停时出现圆形底色，按下时略微缩小。
struct PlayerButtonStyle: ButtonStyle {
    var isActive = false
    var tone: PlayerControlTone = .standard

    func makeBody(configuration: Configuration) -> some View {
        PlayerButtonBody(configuration: configuration, isActive: isActive, tone: tone)
    }
}

private struct PlayerButtonBody: View {
    let configuration: ButtonStyleConfiguration
    let isActive: Bool
    let tone: PlayerControlTone
    @Environment(\.isEnabled) private var isEnabled
    @State private var isHovering = false

    var body: some View {
        configuration.label
            .foregroundStyle(isActive ? Color.dizzyGold : tone.primary)
            .opacity(isEnabled ? 1 : 0.35)
            .padding(6)
            .background(background, in: .circle)
            .scaleEffect(configuration.isPressed ? 0.88 : 1)
            .contentShape(.circle)
            .onHover { isHovering = $0 }
            .animation(.snappy(duration: 0.15), value: configuration.isPressed)
    }

    /// 开启的模式（随机、循环、歌词面板）用金色底标出，悬停时浅灰底。
    private var background: Color {
        if isActive { return Color.dizzyGold.opacity(isHovering ? 0.24 : 0.16) }
        return tone.primary.opacity(isHovering && isEnabled ? 0.1 : 0)
    }
}

/// 随机、上一首、播放 / 暂停、下一首、循环。
struct TransportControls: View {
    var showsModes = true
    var scale: CGFloat = 1
    var tone: PlayerControlTone = .standard
    @Environment(PlayerStore.self) private var player

    var body: some View {
        let hasTrack = player.currentTrack != nil
        HStack(spacing: 6 * scale) {
            if showsModes {
                Button { player.toggleShuffle() } label: {
                    Image(systemName: "shuffle").font(.system(size: 13 * scale, weight: .semibold))
                }
                .buttonStyle(PlayerButtonStyle(isActive: player.isShuffled, tone: tone))
                .disabled(!hasTrack || player.isDiscovery)
                .help(player.isShuffled ? "关闭随机播放" : "随机播放")
            }
            Button { player.previous() } label: {
                Image(systemName: "backward.fill").font(.system(size: 17 * scale))
            }
            .buttonStyle(PlayerButtonStyle(tone: tone))
            .disabled(!hasTrack || !player.canPlayPrevious)
            .help("上一首")
            Button { player.togglePlayback() } label: {
                Image(systemName: player.isPlaying ? "pause.fill" : "play.fill")
                    .font(.system(size: 24 * scale))
                    .contentTransition(.symbolEffect(.replace))
                    .frame(width: 28 * scale, height: 28 * scale)
            }
            .buttonStyle(PlayerButtonStyle(tone: tone))
            .disabled(!hasTrack)
            .help(player.isPlaying ? "暂停" : "播放")
            Button { player.next() } label: {
                Image(systemName: "forward.fill").font(.system(size: 17 * scale))
            }
            .buttonStyle(PlayerButtonStyle(tone: tone))
            .disabled(!hasTrack || !player.canPlayNext)
            .help("下一首")
            if showsModes {
                Button { player.cycleRepeatMode() } label: {
                    Image(systemName: player.repeatMode.systemImage).font(.system(size: 13 * scale, weight: .semibold))
                }
                .buttonStyle(PlayerButtonStyle(isActive: player.repeatMode != .off, tone: tone))
                .disabled(!hasTrack || player.isDiscovery)
                .help(player.repeatMode.accessibilityTitle)
            }
        }
    }
}

/// 细进度条：拖动或点击跳转，两侧显示已播放与剩余时间。
struct ProgressScrubber: View {
    var tone: PlayerControlTone = .standard
    var showsTimes = true
    @Environment(PlayerStore.self) private var player
    @State private var scrubbingPosition: TimeInterval?
    @State private var isHovering = false

    var body: some View {
        let duration = player.duration
        let position = scrubbingPosition ?? min(player.progress, duration)
        let fraction = duration > 0 ? min(max(position / duration, 0), 1) : 0
        let isActive = isHovering || scrubbingPosition != nil
        HStack(spacing: 8) {
            if showsTimes { time(TimeFormat.clock(position)) }
            GeometryReader { proxy in
                ZStack(alignment: .leading) {
                    Capsule().fill(tone.track)
                    Capsule().fill(isActive ? tone.primary : tone.fill)
                        .frame(width: proxy.size.width * fraction)
                }
                .frame(height: isActive ? 6 : 4)
                .frame(maxHeight: .infinity)
                .contentShape(.rect)
                .gesture(DragGesture(minimumDistance: 0)
                    .onChanged { value in
                        guard duration > 0 else { return }
                        scrubbingPosition = min(max(value.location.x / max(proxy.size.width, 1), 0), 1) * duration
                    }
                    .onEnded { value in
                        guard duration > 0 else { return }
                        player.seek(to: min(max(value.location.x / max(proxy.size.width, 1), 0), 1) * duration)
                        scrubbingPosition = nil
                    })
            }
            .frame(height: 12)
            .onHover { isHovering = $0 }
            .animation(.snappy(duration: 0.15), value: isActive)
            if showsTimes { time(duration > 0 ? "−" + TimeFormat.clock(max(duration - position, 0)) : "--:--") }
        }
        .onChange(of: player.currentTrack?.id) { scrubbingPosition = nil }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("播放进度")
        .accessibilityValue(duration > 0 ? "\(TimeFormat.clock(position))，共 \(TimeFormat.clock(duration))" : "")
        .accessibilityAdjustableAction { direction in
            switch direction {
            case .increment: player.seek(to: player.progress + 10)
            case .decrement: player.seek(to: player.progress - 10)
            @unknown default: break
            }
        }
    }

    private func time(_ text: String) -> some View {
        Text(text)
            .font(.caption2.monospacedDigit())
            .foregroundStyle(tone.secondary)
            .frame(minWidth: 34, alignment: .center)
    }
}

/// 本 App 的音量滑块，左侧图标随音量变化，点击静音 / 恢复。
struct VolumeControl: View {
    var tone: PlayerControlTone = .standard
    var width: CGFloat = 92
    @Environment(PlayerStore.self) private var player
    @AppStorage("player.volumeBeforeMute") private var volumeBeforeMute = 0.6

    var body: some View {
        HStack(spacing: 4) {
            Button {
                if player.volume > 0 {
                    volumeBeforeMute = Double(player.volume)
                    player.volume = 0
                } else {
                    player.volume = Float(max(volumeBeforeMute, 0.1))
                }
            } label: {
                Image(systemName: symbol)
                    .font(.system(size: 12, weight: .medium))
                    .frame(width: 18)
            }
            .buttonStyle(PlayerButtonStyle(tone: tone))
            .help(player.volume > 0 ? "静音" : "取消静音")
            Slider(value: Binding(get: { Double(player.volume) }, set: { player.volume = Float($0) }), in: 0...1)
                .controlSize(.mini)
                .frame(width: width)
                .tint(tone == .onDark ? .white : .secondary)
                .accessibilityLabel("音量")
        }
    }

    private var symbol: String {
        switch player.volume {
        case 0: "speaker.slash.fill"
        case ..<0.34: "speaker.wave.1.fill"
        case ..<0.67: "speaker.wave.2.fill"
        default: "speaker.wave.3.fill"
        }
    }
}

/// AirPlay 输出选择（系统的 AVRoutePickerView）。
struct AirPlayButton: NSViewRepresentable {
    @Environment(PlayerStore.self) private var player

    func makeNSView(context: Context) -> AVRoutePickerView {
        let view = AVRoutePickerView()
        view.isRoutePickerButtonBordered = false
        view.player = player.routingPlayer
        view.setRoutePickerButtonColor(NSColor(Color.dizzyGold), for: .active)
        view.setAccessibilityLabel(String(localized: "AirPlay"))
        return view
    }

    func updateNSView(_ view: AVRoutePickerView, context: Context) {
        view.player = player.routingPlayer
    }
}
