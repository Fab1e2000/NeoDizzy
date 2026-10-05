import SwiftUI

/// 专辑页页头：左侧封面，右侧信息栏与封面等高。
/// 标题、艺术家和信息行贴着封面顶部，介绍摘要和按钮贴着封面底部，中间留白随封面尺寸伸缩，
/// 短标题不会悬在一大片空白下面。标题字号按长度分档（参考 Feishin 的 LibraryHeader，中日韩字符按更宽计）。
/// 始终左右排列，窗口变窄时只缩小封面、把次要按钮换成图标，不改成手机式的居中竖排。
struct AlbumHeader<Subtitle: View, Actions: View, Footer: View>: View {
    let artworkURL: URL?
    let title: String
    let metadata: String
    @ViewBuilder var subtitle: Subtitle
    @ViewBuilder var actions: Actions
    /// 介绍摘要，放在信息行与按钮之间。
    @ViewBuilder var footer: Footer
    @State private var artworkSide: CGFloat = 250
    @State private var isCompact = false

    var body: some View {
        HStack(alignment: .top, spacing: 28) {
            ArtworkImage(url: artworkURL, cornerRadius: 8, decodeSize: AlbumArtworkSize.hero)
                .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(.primary.opacity(0.08), lineWidth: 0.5))
                .compositingGroup()
                .shadow(color: .black.opacity(0.3), radius: 10, y: 5)
                .frame(width: artworkSide, height: artworkSide)
            VStack(alignment: .leading, spacing: 0) {
                Text(title)
                    .font(.system(size: AlbumHeaderMetrics.titleSize(for: title), weight: .bold))
                    .lineLimit(3)
                    .minimumScaleFactor(0.85)
                    .textSelection(.enabled)
                    .accessibilityAddTraits(.isHeader)
                subtitle
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(Color.dizzyAccent)
                    .lineLimit(2)
                    .padding(.top, 6)
                if !metadata.isEmpty {
                    Text(metadata)
                        .font(.note.weight(.medium))
                        .foregroundStyle(.secondary)
                        .textCase(.uppercase)
                        .padding(.top, 6)
                }
                Spacer(minLength: 14)
                footer
                    .font(.note)
                    .padding(.bottom, 12)
                HStack(spacing: 8) {
                    actions
                }
                .environment(\.albumHeaderIsCompact, isCompact)
            }
            .padding(.top, 4)
            .frame(maxWidth: .infinity, minHeight: artworkSide, alignment: .leading)
        }
        // 封面边长按宽度分档（160–250），只有跨档时才重新布局。
        .onGeometryChange(for: CGFloat.self) { min(250, max(160, (($0.size.width * 0.28) / 30).rounded(.down) * 30)) } action: { artworkSide = $0 }
        .onGeometryChange(for: Bool.self) { $0.size.width < 820 } action: { isCompact = $0 }
    }
}

enum AlbumHeaderMetrics {
    /// 标题越长字号越小：中日韩字符按 2 个单位计，其余按 1 个。
    static func titleSize(for title: String) -> CGFloat {
        let length = title.unicodeScalars.reduce(0) { $0 + (isWide($1) ? 2 : 1) }
        switch length {
        case ..<24: return 34
        case ..<40: return 30
        case ..<60: return 26
        default: return 22
        }
    }

    private static func isWide(_ scalar: Unicode.Scalar) -> Bool {
        switch scalar.value {
        case 0x1100...0x11FF, 0x2E80...0x9FFF, 0xAC00...0xD7AF, 0xF900...0xFAFF, 0xFF00...0xFF60, 0x20000...0x3FFFF: true
        default: false
        }
    }

    /// 合辑的艺术家常写成「A / B / C / …」：超过三位时只列前三位并注明总数，完整名单放在悬停提示里。
    static func condensedArtists(_ artist: String) -> String {
        let separators = CharacterSet(charactersIn: "/、;；")
        let names = artist.components(separatedBy: separators)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
        guard names.count > 3 else { return artist }
        return String(localized: "\(names.prefix(3).joined(separator: "、")) 等 \(names.count) 位艺术家")
    }
}

extension AlbumHeader where Footer == EmptyView {
    init(artworkURL: URL?, title: String, metadata: String,
         @ViewBuilder subtitle: () -> Subtitle, @ViewBuilder actions: () -> Actions) {
        self.init(artworkURL: artworkURL, title: title, metadata: metadata,
                  subtitle: subtitle, actions: actions, footer: { EmptyView() })
    }
}

extension EnvironmentValues {
    @Entry var albumHeaderIsCompact = false
}

/// 页头里的次要按钮（下载、购买等）：窄布局下只显示图标，悬停显示完整名称。
struct HeaderSecondaryLabel: View {
    let title: String
    let systemImage: String
    @Environment(\.albumHeaderIsCompact) private var isCompact

    var body: some View {
        Group {
            if isCompact {
                Image(systemName: systemImage)
            } else {
                Label(title, systemImage: systemImage)
            }
        }
        .help(title)
    }
}

/// Music 风格的主按钮：强调色浅底、强调色文字的圆角矩形。
struct AccentPillButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        AccentPillBody(configuration: configuration)
    }
}

private struct AccentPillBody: View {
    let configuration: ButtonStyleConfiguration
    @Environment(\.isEnabled) private var isEnabled
    @State private var isHovering = false

    var body: some View {
        configuration.label
            .font(.system(size: 13, weight: .semibold))
            .foregroundStyle(Color.dizzyAccent)
            .padding(.horizontal, 16)
            .frame(height: 30)
            .background(Color.dizzyAccent.opacity(configuration.isPressed ? 0.32 : isHovering ? 0.24 : 0.17),
                        in: .rect(cornerRadius: 7))
            .opacity(isEnabled ? 1 : 0.4)
            .contentShape(.rect)
            .onHover { isHovering = $0 }
    }
}

/// 页头的次要按钮：无底色，悬停时出现浅灰底。
struct HeaderSecondaryButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        HeaderSecondaryBody(configuration: configuration)
    }
}

private struct HeaderSecondaryBody: View {
    let configuration: ButtonStyleConfiguration
    @Environment(\.isEnabled) private var isEnabled
    @State private var isHovering = false

    var body: some View {
        configuration.label
            .font(.system(size: 13, weight: .medium))
            .foregroundStyle(.secondary)
            .padding(.horizontal, 10)
            .frame(height: 30)
            .background(.primary.opacity(configuration.isPressed ? 0.14 : isHovering ? 0.08 : 0), in: .rect(cornerRadius: 7))
            .opacity(isEnabled ? 1 : 0.4)
            .contentShape(.rect)
            .onHover { isHovering = $0 }
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
        }
        .buttonStyle(AccentPillButtonStyle())
        .disabled(isEmpty)
        Button { play(true) } label: {
            Label("随机播放", systemImage: "shuffle")
        }
        .buttonStyle(AccentPillButtonStyle())
        .disabled(isEmpty)
    }
}
