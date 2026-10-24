import SwiftUI
import UIKit

/// A native anchored menu, matching the player's More button rather than
/// presenting a confirmation sheet. Merely rendering it starts no requests.
struct NowPlayingArtistButton: UIViewRepresentable {
    let track: Track
    @Environment(ModuleRegistry.self) private var modules: ModuleRegistry?
    @Environment(\.openRoute) private var openRoute

    func makeCoordinator() -> PlayerArtistMenuController { PlayerArtistMenuController() }

    func makeUIView(context: Context) -> UIButton {
        let button = UIButton(type: .system)
        button.contentHorizontalAlignment = .leading
        button.titleLabel?.font = .systemFont(ofSize: 20)
        button.titleLabel?.lineBreakMode = .byTruncatingTail
        button.setTitleColor(.white.withAlphaComponent(0.64), for: .normal)
        button.showsMenuAsPrimaryAction = true
        button.accessibilityHint = String(localized: "显示前往艺术家的选项")
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
        if changed || button.menu == nil { button.menu = coordinator.menu() }
    }

    func sizeThatFits(_ proposal: ProposedViewSize, uiView: UIButton, context: Context) -> CGSize? {
        CGSize(width: proposal.width ?? uiView.intrinsicContentSize.width, height: 26)
    }

    static func dismantleUIView(_ uiView: UIButton, coordinator: PlayerArtistMenuController) {
        coordinator.cancel()
    }
}

/// Shared request lifetime for both artist entry points. The More menu contains
/// a plain action; only choosing it replaces the visible menu with lazy artists.
@MainActor final class PlayerArtistMenuController {
    private var track: Track?
    private weak var modules: ModuleRegistry?
    private var open: (AppRoute) -> Void = { _ in }
    private var request: Task<Void, Never>?
    private var generation = UUID()

    @discardableResult
    func bind(track: Track?, modules: ModuleRegistry?, open: @escaping (AppRoute) -> Void) -> Bool {
        let changed = self.track?.id != track?.id || self.modules !== modules
        if changed { cancel() }
        self.track = track
        self.modules = modules
        self.open = open
        return changed
    }

    func cancel() {
        generation = UUID()
        request?.cancel()
        request = nil
    }

    func menu() -> UIMenu {
        UIMenu(children: [UIDeferredMenuElement.uncached { [weak self] completion in
            guard let self else { completion([]); return }
            self.load(completion: completion)
        }])
    }

    func action(for button: UIButton) -> UIAction? {
        guard let track, !track.artists.isEmpty, modules != nil else { return nil }
        return UIAction(title: String(localized: "查看艺术家"), image: UIImage(systemName: "person"),
                        attributes: .keepsMenuPresented) { [weak self, weak button] _ in
            guard let self else { return }
            button?.contextMenuInteraction?.updateVisibleMenu { _ in self.menu() }
        }
    }

    func load(completion: @escaping ([UIMenuElement]) -> Void) {
        cancel()
        guard let track, let modules else { completion([]); return }
        let token = generation
        request = Task { [weak self] in
            do {
                let destinations = try await modules.artistDestinations(for: track)
                try Task.checkCancellation()
                guard let self, self.generation == token else { completion([]); return }
                let items = destinations.map { destination in
                    UIAction(title: String(localized: "前往\(destination.name)"), image: UIImage(systemName: "person")) { [weak self] _ in
                        guard let self, self.generation == token else { return }
                        self.open(destination.route)
                    }
                }
                completion(items.isEmpty ? [Self.message("此来源暂未提供艺术家页面")] : items)
            } catch is CancellationError {
                completion([])
            } catch {
                guard let self, self.generation == token, !Task.isCancelled else { completion([]); return }
                completion([Self.message("加载失败，请重新打开重试")])
            }
        }
    }

    private static func message(_ title: String) -> UIAction {
        UIAction(title: title, attributes: .disabled) { _ in }
    }
}
