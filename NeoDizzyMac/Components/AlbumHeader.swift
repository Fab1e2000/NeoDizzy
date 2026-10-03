import SwiftUI

/// 专辑页页头，布局参考 Music：左侧大封面，右侧底部对齐标题、艺术家（强调色）、信息行和播放按钮。
struct AlbumHeader<Subtitle: View, Actions: View, Footer: View>: View {
    let artworkURL: URL?
    let title: String
    let metadata: String
    @ViewBuilder var subtitle: Subtitle
    @ViewBuilder var actions: Actions
    @ViewBuilder var footer: Footer

    var body: some View {
        HStack(alignment: .bottom, spacing: 30) {
            ArtworkImage(url: artworkURL, cornerRadius: 10, decodeSize: AlbumArtworkSize.hero)
                .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(.primary.opacity(0.08), lineWidth: 0.5))
                .shadow(color: .black.opacity(0.22), radius: 14, y: 8)
                // 窗口变窄时封面跟着缩小，给右侧标题和按钮留出空间。
                .containerRelativeFrame(.horizontal) { width, _ in min(270, max(170, width * 0.3)) }
            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.system(size: 28, weight: .bold))
                    .lineLimit(3)
                    .textSelection(.enabled)
                subtitle
                    .font(.system(size: 22))
                    .foregroundStyle(Color.dizzyGold)
                    .lineLimit(1)
                if !metadata.isEmpty {
                    Text(metadata)
                        .font(.callout.weight(.medium))
                        .foregroundStyle(.secondary)
                        .padding(.top, 2)
                }
                footer
                    .padding(.top, 8)
                // 按钮保持完整宽度，放不下时换行。
                FlowLayout(spacing: 10, lineSpacing: 10) {
                    actions
                }
                .padding(.top, 14)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.top, 8)
    }
}

extension AlbumHeader where Footer == EmptyView {
    init(artworkURL: URL?, title: String, metadata: String,
         @ViewBuilder subtitle: () -> Subtitle, @ViewBuilder actions: () -> Actions) {
        self.init(artworkURL: artworkURL, title: title, metadata: metadata,
                  subtitle: subtitle, actions: actions, footer: { EmptyView() })
    }
}

/// 播放与随机播放两个主按钮。
struct AlbumPlayButtons: View {
    let isEmpty: Bool
    var isPreview = false
    let play: (Bool) -> Void

    var body: some View {
        Button { play(false) } label: {
            Label(isPreview ? "试听" : "播放", systemImage: "play.fill")
                .frame(minWidth: 72)
        }
        .buttonStyle(.borderedProminent)
        .fixedSize()
        .disabled(isEmpty)
        Button { play(true) } label: {
            Label("随机播放", systemImage: "shuffle")
                .frame(minWidth: 72)
        }
        .buttonStyle(.borderedProminent)
        .fixedSize()
        .disabled(isEmpty)
    }
}

/// 页头右侧的圆形次要按钮（更多、在浏览器中打开）。
struct CircleIconButton: View {
    let title: String
    let systemImage: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .frame(width: 18, height: 18)
        }
        .buttonStyle(.bordered)
        .buttonBorderShape(.circle)
        .help(title)
        .accessibilityLabel(title)
    }
}
