import SwiftUI

/// 迷你播放器：一张方形封面，悬停时显示曲目信息、进度与控制，参考 Music 的迷你播放器。
struct MiniPlayerWindow: View {
    @Environment(MacAppModel.self) private var model
    @Environment(PlayerStore.self) private var player
    @Environment(\.openWindow) private var openWindow
    @Environment(\.dismissWindow) private var dismissWindow
    @AppStorage("miniPlayer.floats") private var floats = true
    @State private var isHovering = false

    var body: some View {
        ZStack(alignment: .bottom) {
            if player.currentTrack != nil {
                ArtworkImage(url: player.currentTrack?.coverURL, cornerRadius: 0, decodeSize: CGSize(width: 600, height: 600))
            } else {
                ZStack {
                    Rectangle().fill(.quaternary)
                    Image(systemName: "music.note").font(.system(size: 48)).foregroundStyle(.tertiary)
                }
            }
            if isHovering || player.currentTrack == nil {
                controls
                    .transition(.opacity)
            }
        }
        .frame(width: 300, height: 300)
        .clipShape(.rect(cornerRadius: 12))
        .onHover { hovering in withAnimation(.easeOut(duration: 0.18)) { isHovering = hovering } }
        .containerBackground(.clear, for: .window)
        .environment(\.colorScheme, .dark)
        .onAppear {
            if model.openWindow == nil {
                let openWindow = openWindow
                model.openWindow = { openWindow(id: $0) }
            }
        }
    }

    private var controls: some View {
        VStack(spacing: 8) {
            HStack {
                Button { dismissWindow() } label: {
                    Image(systemName: "xmark").font(.system(size: 11, weight: .bold))
                }
                .buttonStyle(PlayerButtonStyle(tone: .onDark))
                .help("关闭迷你播放器")
                Spacer()
                Button { floats.toggle() } label: {
                    Image(systemName: floats ? "pin.fill" : "pin").font(.system(size: 12))
                }
                .buttonStyle(PlayerButtonStyle(isActive: floats, tone: .onDark))
                .help(floats ? "取消置顶" : "置于顶层")
                Button { openWindow(id: SceneID.main) } label: {
                    Image(systemName: "macwindow").font(.system(size: 12))
                }
                .buttonStyle(PlayerButtonStyle(tone: .onDark))
                .help("打开主窗口")
            }
            Spacer()
            if let track = player.currentTrack {
                VStack(spacing: 2) {
                    Text(track.title).font(.headline).lineLimit(1)
                    Text(track.artists).font(.callout).foregroundStyle(.white.opacity(0.7)).lineLimit(1)
                }
                .foregroundStyle(.white)
                ProgressScrubber(tone: .onDark)
            } else {
                Text("没有正在播放的歌曲").font(.callout).foregroundStyle(.white.opacity(0.7))
            }
            TransportControls(tone: .onDark)
        }
        .padding(.horizontal, 12)
        .padding(.top, 10)
        .padding(.bottom, 12)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(LinearGradient(colors: [.black.opacity(0.35), .black.opacity(0.1), .black.opacity(0.75)],
                                   startPoint: .top, endPoint: .bottom))
    }
}
