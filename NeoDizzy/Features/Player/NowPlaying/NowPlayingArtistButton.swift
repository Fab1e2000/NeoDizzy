import SwiftUI
import UIKit

/// 作者名字形显示提亮后的背景，透明按钮保留原有点击和菜单。
struct NowPlayingArtistButton: View {
    let track: Track
    /// 为 false 时只显示文字（左右滑动切歌时相邻曲目的预览），大小和按钮一样。
    var interactive = true
    var lineHeight: CGFloat = 26
    var fontSize: CGFloat = 20

    var body: some View {
        if interactive {
            NowPlayingArtistMenuButton(track: track, lineHeight: lineHeight)
                .background(alignment: .leading) {
                    label.accessibilityHidden(true)
                }
        } else {
            label.frame(height: lineHeight)
        }
    }

    private var label: some View {
        NowPlayingVibrantLabel(text: track.artists, fontSize: fontSize)
            .frame(maxWidth: .infinity, alignment: .leading)
            .allowsHitTesting(false)
    }
}

/// Shares the page's rendered image: no extra artwork requests or palette calculation.
/// The brighter copy is confined to glyphs; the page background is untouched.
struct NowPlayingVibrantLabel: View {
    let text: String
    let fontSize: CGFloat
    @Environment(\.nowPlayingBackdropImage) private var image
    @Environment(\.nowPlayingBackdropAnchor) private var backdropAnchor
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var glyphs: some View {
        NowPlayingGlyphMask(text: text, fontSize: fontSize)
    }

    var body: some View {
        glyphs.hidden()
            .overlay {
                ZStack {
                    Color(white: 0.88)
                    if let image, let backdropAnchor {
                        NowPlayingAlignedBackdrop(image: image, anchor: backdropAnchor,
                                                  animated: !reduceMotion)
                            .brightness(0.65)
                    }
                }
                .clipped()
                .mask { glyphs }
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(text)
            .allowsHitTesting(false)
    }
}

/// Retain the existing UIKit font metrics and truncation for the glyph mask.
private struct NowPlayingGlyphMask: UIViewRepresentable {
    let text: String
    let fontSize: CGFloat

    func makeUIView(context: Context) -> UILabel {
        let label = UILabel()
        label.textColor = .white
        label.numberOfLines = 1
        label.lineBreakMode = .byTruncatingTail
        label.isAccessibilityElement = false
        return label
    }

    func updateUIView(_ label: UILabel, context: Context) {
        label.text = text
        let baseFont = UIFont.systemFont(ofSize: fontSize)
        label.font = fontSize == 20 ? baseFont : UIFontMetrics(
            forTextStyle: fontSize == 13 ? .footnote : .subheadline
        ).scaledFont(for: baseFont, compatibleWith: label.traitCollection)
    }

    func sizeThatFits(_ proposal: ProposedViewSize, uiView: UILabel, context: Context) -> CGSize? {
        CGSize(width: proposal.width ?? uiView.intrinsicContentSize.width,
               height: uiView.font.lineHeight)
    }
}

/// A native anchored menu, matching the player's More button rather than
/// presenting a confirmation sheet. Merely rendering it starts no requests.
private struct NowPlayingArtistMenuButton: UIViewRepresentable {
    let track: Track
    let lineHeight: CGFloat
    @Environment(ModuleRegistry.self) private var modules: ModuleRegistry?
    @Environment(\.openRoute) private var openRoute

    func makeCoordinator() -> PlayerArtistMenuController { PlayerArtistMenuController() }

    func makeUIView(context: Context) -> UIButton {
        let button = UIButton(type: .system)
        button.contentHorizontalAlignment = .leading
        button.titleLabel?.font = .systemFont(ofSize: 20)
        button.titleLabel?.lineBreakMode = .byTruncatingTail
        // 原生 Vibrancy 负责文字，这里只保留点击区域和菜单。
        button.setTitleColor(.clear, for: .normal)
        button.accessibilityHint = String(localized: "前往艺术家")
        configure(button, coordinator: context.coordinator)
        return button
    }

    func updateUIView(_ button: UIButton, context: Context) {
        configure(button, coordinator: context.coordinator)
    }

    private func configure(_ button: UIButton, coordinator: PlayerArtistMenuController) {
        let changed = coordinator.bind(track: track, modules: modules, open: { openRoute($0) })
        button.setTitle(track.artists, for: .normal)
        button.accessibilityLabel = track.artists
        button.isEnabled = modules != nil && !track.artists.isEmpty
        guard changed || !coordinator.hasConfiguredButton else { return }
        coordinator.hasConfiguredButton = true
        // 多位作者弹出名字菜单，一位作者点了直接进入；都不需要等待加载。
        let menu = coordinator.menu()
        button.menu = menu
        button.showsMenuAsPrimaryAction = menu != nil
        button.removeAction(identifiedBy: Self.openActionID, for: .primaryActionTriggered)
        if menu == nil {
            button.addAction(UIAction(identifier: Self.openActionID) { [weak coordinator] _ in
                coordinator?.openSingle()
            }, for: .primaryActionTriggered)
        }
    }

    private static let openActionID = UIAction.Identifier("neodizzy.player.artist.open")

    func sizeThatFits(_ proposal: ProposedViewSize, uiView: UIButton, context: Context) -> CGSize? {
        CGSize(width: proposal.width ?? uiView.intrinsicContentSize.width, height: lineHeight)
    }

    static func dismantleUIView(_ uiView: UIButton, coordinator: PlayerArtistMenuController) {
        coordinator.cancel()
    }
}

/// 作者名的两个入口（作者名按钮、「更多」菜单）共用。不发任何请求：按本地拆出的名字立刻给出选项，
/// 点了就直接进入艺人页，页面里再去解析（见 PlayerArtistPage）。本地音乐直接进资料库的艺人。
@MainActor final class PlayerArtistMenuController {
    private var track: Track?
    private weak var modules: ModuleRegistry?
    private var open: (AppRoute) -> Void = { _ in }
    /// 作者名按钮的菜单和点击动作已经按当前歌曲配置过。
    var hasConfiguredButton = false

    @discardableResult
    func bind(track: Track?, modules: ModuleRegistry?, open: @escaping (AppRoute) -> Void) -> Bool {
        let changed = self.track?.id != track?.id || self.modules !== modules
        self.track = track
        self.modules = modules
        self.open = open
        return changed
    }

    /// 以前用来取消加载请求；现在没有请求，保留给调用方的生命周期。
    func cancel() {}

    /// 每位作者一个去处；来源只有一个去处（比如 DizzyLab 的社团页）时只有一项。
    func destinations() -> [(name: String, route: AppRoute)] {
        guard let track, let modules, !track.artists.isEmpty else { return [] }
        if modules.artistNavigation(for: track) == .single {
            return [(track.artists, .page(track.artists) {
                PlayerArtistPage(track: track, name: track.artists, index: 0, count: 1)
            })]
        }
        let split = LibraryArtistNames.split(track.artists)
        let names = split.isEmpty ? [track.artists] : split
        return names.enumerated().map { index, name in
            let route: AppRoute = track.localSource != nil
                ? .libraryArtist(name, filter: .all)
                : .page(name) { PlayerArtistPage(track: track, name: name, index: index, count: names.count) }
            return (name, route)
        }
    }

    /// 多位作者时的菜单；只有一位时返回 nil，点按钮直接进入。
    func menu() -> UIMenu? {
        let destinations = destinations()
        guard destinations.count > 1 else { return nil }
        return UIMenu(children: destinations.map { destination in
            UIAction(title: String(localized: "前往\(destination.name)"), image: UIImage(systemName: "person")) { [weak self] _ in
                self?.open(destination.route)
            }
        })
    }

    /// 只有一位作者时直接打开。
    func openSingle() {
        guard let only = destinations().first, destinations().count == 1 else { return }
        open(only.route)
    }

    /// 「更多」菜单里的入口：一位作者是直接前往的按钮，多位是子菜单。
    func action(for button: UIButton) -> UIMenuElement? {
        let destinations = destinations()
        guard !destinations.isEmpty else { return nil }
        if destinations.count == 1, let only = destinations.first {
            return UIAction(title: String(localized: "查看艺术家"), image: UIImage(systemName: "person")) { [weak self] _ in
                self?.open(only.route)
            }
        }
        return UIMenu(title: String(localized: "查看艺术家"), image: UIImage(systemName: "person"),
                      children: menu()?.children ?? [])
    }
}
