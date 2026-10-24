import SwiftUI
import UIKit

/// SwiftUI's per-item toolbar appearance can override UITabBar.tintColor with
/// labelColor. Keep the native tab bar and its item appearances under the same
/// shell-owned palette; leave the system's glass, spacing and backgrounds intact.
struct ShellTabBarAppearance: UIViewControllerRepresentable {
    let colorScheme: ColorScheme
    let accent: AccentPalette
    let isSelected: Bool

    func makeUIViewController(context: Context) -> Controller { Controller() }
    func updateUIViewController(_ controller: Controller, context: Context) {
        controller.style = colorScheme == .dark ? .dark : .light
        controller.color = UIColor(accent.color(for: colorScheme))
        controller.isSelected = isSelected
        controller.apply()
    }

    final class Controller: UIViewController {
        var style: UIUserInterfaceStyle = .light
        var color = UIColor.label
        var isSelected = false
        override func loadView() { view = UIView(); view.isUserInteractionEnabled = false }
        override func didMove(toParent parent: UIViewController?) { super.didMove(toParent: parent); apply() }
        override func viewWillAppear(_ animated: Bool) { super.viewWillAppear(animated); apply() }
        override func viewDidLayoutSubviews() { super.viewDidLayoutSubviews(); apply() }

        func apply() {
            guard isSelected, let bar = tabBarController?.tabBar else { return }
            if bar.overrideUserInterfaceStyle != style { bar.overrideUserInterfaceStyle = style }
            if bar.tintColor != color { bar.tintColor = color }
            if let appearance = updated(bar.standardAppearance) { bar.standardAppearance = appearance }
            if let edge = bar.scrollEdgeAppearance, let appearance = updated(edge) { bar.scrollEdgeAppearance = appearance }
            for item in bar.items ?? [] {
                if let local = item.standardAppearance, let appearance = updated(local) { item.standardAppearance = appearance }
                if let edge = item.scrollEdgeAppearance, let appearance = updated(edge) { item.scrollEdgeAppearance = appearance }
            }
        }

        private func updated(_ original: UITabBarAppearance) -> UITabBarAppearance? {
            let layouts = [original.stackedLayoutAppearance, original.inlineLayoutAppearance, original.compactInlineLayoutAppearance]
            guard layouts.contains(where: { $0.selected.iconColor != color || ($0.selected.titleTextAttributes[.foregroundColor] as? UIColor) != color }) else { return nil }
            let appearance = original.copy()
            for layout in [appearance.stackedLayoutAppearance, appearance.inlineLayoutAppearance, appearance.compactInlineLayoutAppearance] {
                layout.selected.iconColor = color
                layout.selected.titleTextAttributes[.foregroundColor] = color
            }
            return appearance
        }
    }
}
