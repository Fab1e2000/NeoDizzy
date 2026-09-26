// 布局移植自 MeloX（GPLv3）Features/Player/NowPlaying/NowPlayingBottomControls.swift、NowPlayingControls.swift、
// NowPlayingMenuButton.swift：去掉歌词、AutoMix、音质选择和一起听；进度条改为自己处理拖动（支持点按跳转），
// 左下角的歌词按钮换成隔空播放。

import AVKit
import MediaPlayer
import SwiftUI
import UIKit

/// 播放页的两个页面：大封面，或者「继续播放」队列。
enum NowPlayingPage {
    case artwork
    case queue
}

/// 播放页底部的控件：进度、播放控制、音量、页面切换。高度固定，页面内容在它上方留出同样的空间。
struct NowPlayingBottomControls: View {
    static let coreHeight: CGFloat = 279

    @Binding var page: NowPlayingPage

    var body: some View {
        VStack(spacing: 0) {
            NowPlayingProgressControl()
            Color.clear.frame(height: 19)
            NowPlayingTransportControls()
            Color.clear.frame(height: 31)
            NowPlayingVolumeControl()
            Color.clear.frame(height: 3)
            NowPlayingPageSelector(page: $page)
        }
        .frame(height: Self.coreHeight)
        // 挡住下面列表的点按，避免点到控件间隙时误触队列里的曲目。
        .background {
            Color.clear
                .contentShape(.rect)
                .onTapGesture {}
        }
    }
}

/// 进度条：按住后跟随手指，松手才跳转，避免拖动中反复请求音频；点一下也能直接跳到那里。
/// 中间显示「试听」「完整版」或播放出错的原因。
struct NowPlayingProgressControl: View {
    @Environment(PlayerStore.self) private var player
    @Environment(\.accessibilityReduceMotion) private var accessibilityReduceMotion
    @State private var scrubbingPosition: TimeInterval?

    var body: some View {
        let duration = player.duration
        let position = scrubbingPosition ?? min(player.progress, duration)
        let fraction = duration > 0 ? min(max(position / duration, 0), 1) : 0
        let isScrubbing = scrubbingPosition != nil

        VStack(spacing: 2) {
            GeometryReader { proxy in
                ZStack(alignment: .leading) {
                    Capsule()
                        .fill(.white.opacity(0.2))
                    Capsule()
                        .fill(.white.opacity(isScrubbing ? 1 : 0.78))
                        .frame(width: proxy.size.width * fraction)
                }
                .frame(height: isScrubbing ? 12 : 7)
                .frame(maxHeight: .infinity)
                .contentShape(.rect)
                .gesture(scrubGesture(width: proxy.size.width, duration: duration))
            }
            .frame(height: 26)
            .animation(accessibilityReduceMotion ? nil : .snappy(duration: 0.2), value: isScrubbing)

            HStack {
                Text(Self.format(position))
                Spacer()
                Text(duration > 0 ? "−" + Self.format(max(duration - position, 0)) : "--:--")
            }
            .overlay { statusLabel }
            .font(.caption2.monospacedDigit())
            .foregroundStyle(.white.opacity(isScrubbing ? 0.85 : 0.5))
        }
        .frame(height: 52)
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

    @ViewBuilder
    private var statusLabel: some View {
        if let issue = player.issue {
            Text(issue)
                .foregroundStyle(DizzyPalette.danger)
                .lineLimit(1)
                .padding(.horizontal, 44)
        } else if player.duration > 0 {
            Text(player.isPreview ? "试听" : "完整版")
                .fontWeight(.medium)
                .padding(.horizontal, 9)
                .padding(.vertical, 4)
                .background(.white.opacity(player.isPreview ? 0.2 : 0.12), in: .rect(cornerRadius: 7))
                .foregroundStyle(.white.opacity(0.86))
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
        guard seconds.isFinite else { return "0:00" }
        let seconds = max(0, Int(seconds))
        return String(format: "%d:%02d", seconds / 60, seconds % 60)
    }
}

/// 上一首、播放 / 暂停、下一首。按下时图标缩小、背后亮起一圈（NowPlayingTransportButtonStyle）。
struct NowPlayingTransportControls: View {
    @Environment(\.accessibilityReduceMotion) private var accessibilityReduceMotion
    @Environment(PlayerStore.self) private var player

    var body: some View {
        HStack {
            Spacer()

            Button {
                player.previous()
            } label: {
                Image(systemName: "backward.fill")
                    .font(.system(size: 34, weight: .medium))
                    .frame(width: 64, height: 64)
                    .contentShape(.circle)
            }
            .buttonStyle(NowPlayingTransportButtonStyle(reducesMotion: accessibilityReduceMotion))
            .disabled(!player.canPlayPrevious)
            .opacity(player.canPlayPrevious ? 1 : 0.4)
            .accessibilityLabel("上一首")

            Spacer()

            Button {
                player.togglePlayback()
            } label: {
                Group {
                    if player.isLoading {
                        ProgressView()
                            .controlSize(.large)
                            .tint(.white)
                    } else {
                        Image(systemName: player.isPlaying ? "pause.fill" : "play.fill")
                            .font(.system(size: 48, weight: .medium))
                            .contentTransition(
                                accessibilityReduceMotion
                                    ? .identity
                                    : .symbolEffect(.replace.downUp.wholeSymbol, options: .speed(1.6))
                            )
                            .animation(
                                accessibilityReduceMotion ? nil : .snappy(duration: 0.2, extraBounce: 0),
                                value: player.isPlaying
                            )
                    }
                }
                .frame(width: 64, height: 64)
                .contentShape(.circle)
            }
            .buttonStyle(NowPlayingTransportButtonStyle(reducesMotion: accessibilityReduceMotion))
            .accessibilityLabel(player.isPlaying ? "暂停" : "播放")

            Spacer()

            Button {
                player.next()
            } label: {
                Image(systemName: "forward.fill")
                    .font(.system(size: 34, weight: .medium))
                    .frame(width: 64, height: 64)
                    .contentShape(.circle)
            }
            .buttonStyle(NowPlayingTransportButtonStyle(reducesMotion: accessibilityReduceMotion))
            .disabled(!player.canPlayNext)
            .opacity(player.canPlayNext ? 1 : 0.4)
            .accessibilityLabel("下一首")

            Spacer()
        }
        .frame(height: 82)
    }
}

/// 系统音量。
struct NowPlayingVolumeControl: View {
    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "speaker.fill")
                .font(.caption2)
            SystemVolumeSlider()
                .frame(maxWidth: .infinity)
                .frame(height: 32)
                .layoutPriority(1)
                .accessibilityLabel("音量")
            Image(systemName: "speaker.wave.3.fill")
                .font(.caption)
        }
        .foregroundStyle(.white.opacity(0.62))
        .frame(height: 42)
    }
}

private final class AlignedSystemVolumeView: MPVolumeView {
    override func volumeSliderRect(forBounds bounds: CGRect) -> CGRect {
        bounds
    }
}

private struct SystemVolumeSlider: UIViewRepresentable {
    func makeUIView(context: Context) -> AlignedSystemVolumeView {
        let volumeView = AlignedSystemVolumeView(frame: CGRect(x: 0, y: 0, width: 200, height: 32))
        volumeView.backgroundColor = .clear
        volumeView.tintColor = .white
        return volumeView
    }

    func updateUIView(_ volumeView: AlignedSystemVolumeView, context: Context) {
        volumeView.tintColor = .white
    }

    func sizeThatFits(_ proposal: ProposedViewSize, uiView: AlignedSystemVolumeView, context: Context) -> CGSize? {
        CGSize(width: proposal.width ?? 200, height: proposal.height ?? 32)
    }
}

/// 底部一行：左边隔空播放，右边切换到「继续播放」队列。
struct NowPlayingPageSelector: View {
    @Environment(\.accessibilityReduceMotion) private var accessibilityReduceMotion
    @Binding var page: NowPlayingPage

    var body: some View {
        HStack {
            AirPlayButton()
                .frame(width: 44, height: 44)
                .accessibilityLabel("隔空播放")

            Spacer()

            let isQueue = page == .queue
            Button {
                withAnimation(accessibilityReduceMotion ? nil : .smooth(duration: 0.3)) {
                    page = isQueue ? .artwork : .queue
                }
            } label: {
                Image(systemName: "list.bullet")
                    .font(.title3)
                    .frame(width: 44, height: 44)
                    .foregroundStyle(isQueue ? .black.opacity(0.68) : .white.opacity(0.72))
                    .background(.white.opacity(isQueue ? 0.68 : 0), in: .circle)
                    .contentShape(.circle)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("继续播放")
            .accessibilityAddTraits(isQueue ? .isSelected : [])
        }
        .padding(.horizontal, 32)
        .foregroundStyle(.white.opacity(0.72))
        .frame(height: 50)
    }
}

private struct AirPlayButton: UIViewRepresentable {
    func makeUIView(context: Context) -> AVRoutePickerView {
        let picker = AVRoutePickerView()
        picker.tintColor = UIColor.white.withAlphaComponent(0.72)
        picker.activeTintColor = UIColor(DizzyPalette.accent)
        picker.prioritizesVideoDevices = false
        return picker
    }

    func updateUIView(_ picker: AVRoutePickerView, context: Context) {}
}

/// 曲目的「…」菜单：前往专辑、在网页中打开。
struct NowPlayingSongActions: View {
    @Environment(PlayerStore.self) private var player
    @Environment(\.openRoute) private var openRoute
    @Environment(\.openURL) private var openURL

    let track: Track

    var body: some View {
        NowPlayingMenuButton { menuItems() }
            .frame(width: 44, height: 44)
    }

    private func menuItems() -> [UIMenuElement] {
        let discID = track.discID
        var items: [UIMenuElement] = [
            UIAction(title: String(localized: "前往专辑「\(track.albumTitle)」"), image: UIImage(systemName: "music.note.list")) { _ in
                openRoute(.disc(id: discID))
            },
        ]
        if player.isPreview {
            items.append(UIAction(title: String(localized: "前往专辑购买"), image: UIImage(systemName: "cart")) { _ in
                openRoute(.disc(id: discID))
            })
        }
        items.append(UIAction(title: String(localized: "在网页中打开"), image: UIImage(systemName: "safari")) { _ in
            openURL(DizzyURL.disc(discID))
        })
        return items
    }
}

/// 由 UIKit 负责按下、滑动、松开整个过程：播放器每秒刷新 SwiftUI，用 SwiftUI 的 Menu 会在手指还按着时被打断。
private struct NowPlayingMenuButton: UIViewRepresentable {
    var items: () -> [UIMenuElement]

    final class Coordinator {
        var items: () -> [UIMenuElement]
        init(items: @escaping () -> [UIMenuElement]) { self.items = items }
    }

    func makeCoordinator() -> Coordinator { Coordinator(items: items) }

    func makeUIView(context: Context) -> UIButton {
        let button = UIButton(type: .system)
        button.setImage(
            UIImage(systemName: "ellipsis", withConfiguration: UIImage.SymbolConfiguration(pointSize: 20, weight: .semibold)),
            for: .normal
        )
        button.tintColor = .white
        button.backgroundColor = UIColor.white.withAlphaComponent(0.15)
        button.layer.cornerRadius = 22
        button.showsMenuAsPrimaryAction = true
        button.accessibilityLabel = String(localized: "更多")
        // 每次打开时再取当前的菜单项，而不是在 updateUIView 里换掉菜单打断正在进行的操作。
        button.menu = UIMenu(children: [UIDeferredMenuElement.uncached { [weak coordinator = context.coordinator] completion in
            completion(coordinator?.items() ?? [])
        }])
        return button
    }

    func updateUIView(_ button: UIButton, context: Context) {
        context.coordinator.items = items
    }
}
