import AppKit
import SwiftUI

/// 全屏播放器：流动的模糊封面背景，左侧大封面与控制，右侧逐行歌词。参考 Music 的全屏播放器。
/// 打开时让窗口进入全屏，关闭时恢复；按 Esc 退出。
struct FullScreenPlayer: View {
    @Environment(MacAppModel.self) private var model
    @Environment(PlayerStore.self) private var player
    @State private var window: NSWindow?
    @State private var enteredFullScreen = false
    @State private var showsLyrics = true

    var body: some View {
        ZStack(alignment: .topLeading) {
            NowPlayingBackground(artworkURL: player.currentTrack?.coverURL)
            GeometryReader { proxy in
                HStack(spacing: 56) {
                    nowPlaying
                        .frame(width: min(max(proxy.size.width * 0.36, 300), 520))
                    if showsLyrics {
                        LyricsPanel(fontSize: proxy.size.width > 1400 ? 40 : 32, tone: .onDark)
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                            .transition(.opacity)
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .padding(.horizontal, 64)
                .padding(.vertical, 48)
            }
            HStack(spacing: 6) {
                Button { model.isFullScreenPlayerPresented = false } label: {
                    Image(systemName: "chevron.down").font(.system(size: 15, weight: .semibold))
                }
                .buttonStyle(PlayerButtonStyle(tone: .onDark))
                .help("退出全屏播放器")
                Spacer()
                Button { withAnimation(.smooth) { showsLyrics.toggle() } } label: {
                    Image(systemName: "quote.bubble").font(.system(size: 15))
                }
                .buttonStyle(PlayerButtonStyle(isActive: showsLyrics, tone: .onDark))
                .help(showsLyrics ? "隐藏歌词" : "显示歌词")
            }
            .padding(.horizontal, 24)
            .padding(.top, 20)
        }
        .ignoresSafeArea()
        .environment(\.colorScheme, .dark)
        .background(WindowReader(window: $window))
        .onExitCommand { model.isFullScreenPlayerPresented = false }
        .onChange(of: window) { _, window in
            guard let window, !window.styleMask.contains(.fullScreen) else { return }
            enteredFullScreen = true
            window.toggleFullScreen(nil)
        }
        .onDisappear {
            if enteredFullScreen, let window, window.styleMask.contains(.fullScreen) { window.toggleFullScreen(nil) }
        }
        .onChange(of: player.currentTrack == nil) { _, isEmpty in
            if isEmpty { model.isFullScreenPlayerPresented = false }
        }
    }

    private var nowPlaying: some View {
        VStack(alignment: .leading, spacing: 22) {
            Spacer(minLength: 0)
            ArtworkImage(url: player.currentTrack?.coverURL, cornerRadius: 12, decodeSize: CGSize(width: 1024, height: 1024))
                .shadow(color: .black.opacity(0.35), radius: 30, y: 16)
            if let track = player.currentTrack {
                VStack(alignment: .leading, spacing: 4) {
                    Text(track.title)
                        .font(.system(size: 24, weight: .bold))
                        .lineLimit(2)
                    Text([track.artists, track.albumTitle].filter { !$0.isEmpty }.joined(separator: " — "))
                        .font(.title3)
                        .foregroundStyle(.white.opacity(0.65))
                        .lineLimit(1)
                }
                .foregroundStyle(.white)
            }
            VStack(spacing: 14) {
                ProgressScrubber(tone: .onDark)
                TransportControls(scale: 1.35, tone: .onDark)
                VolumeControl(tone: .onDark, width: 160)
            }
            Spacer(minLength: 0)
        }
    }
}

/// 取得 SwiftUI 视图所在的 NSWindow。
struct WindowReader: NSViewRepresentable {
    @Binding var window: NSWindow?

    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        DispatchQueue.main.async { window = view.window }
        return view
    }

    func updateNSView(_ view: NSView, context: Context) {
        if view.window !== window { DispatchQueue.main.async { window = view.window } }
    }
}
