import SwiftUI
import UIKit

/// SwiftUI's per-item toolbar appearance can override UITabBar.tintColor with
/// labelColor. Keep the native tab bar and its item appearances under the same
/// shell-owned palette; leave the system's glass, spacing and backgrounds intact.
struct ShellTabBarAppearance: UIViewControllerRepresentable {
    let colorScheme: ColorScheme
    let accent: AccentPalette
    let isSelected: Bool
    /// 再次点按已选中的标签时调用；返回 true 表示已处理（例如回到了根页面），不再滚到顶部。
    var onReselect: () -> Bool = { false }

    func makeUIViewController(context: Context) -> Controller { Controller() }
    func updateUIViewController(_ controller: Controller, context: Context) {
        controller.style = colorScheme == .dark ? .dark : .light
        controller.color = UIColor(accent.color(for: colorScheme))
        controller.isSelected = isSelected
        controller.onReselect = onReselect
        controller.apply()
    }

    final class Controller: UIViewController {
        var style: UIUserInterfaceStyle = .light
        var color = UIColor.label
        var isSelected = false
        var onReselect: () -> Bool = { false }
        override func loadView() { view = UIView(); view.isUserInteractionEnabled = false }
        override func didMove(toParent parent: UIViewController?) { super.didMove(toParent: parent); apply() }
        override func viewWillAppear(_ animated: Bool) { super.viewWillAppear(animated); apply() }
        override func viewDidLayoutSubviews() { super.viewDidLayoutSubviews(); apply() }

        func apply() {
            guard isSelected, let tabBarController else { return }
            installReselectHandling(on: tabBarController)
            let bar = tabBarController.tabBar
            if bar.overrideUserInterfaceStyle != style { bar.overrideUserInterfaceStyle = style }
            if bar.tintColor != color { bar.tintColor = color }
            if let appearance = updated(bar.standardAppearance) { bar.standardAppearance = appearance }
            if let edge = bar.scrollEdgeAppearance, let appearance = updated(edge) { bar.scrollEdgeAppearance = appearance }
            for item in bar.items ?? [] {
                if let local = item.standardAppearance, let appearance = updated(local) { item.standardAppearance = appearance }
                if let edge = item.scrollEdgeAppearance, let appearance = updated(edge) { item.scrollEdgeAppearance = appearance }
            }
        }

        /// 系统的标签页没有把「再点一次回到顶部」做出来，这里自己做：
        /// 包一层转发给 SwiftUI 原来的代理，只在再次点按已选中的标签时多做一件事。
        /// SwiftUI 的 `Tab` 走的是 `UITab` 那组代理方法（shouldSelectTab），不是按视图控制器选择的旧方法。
        private func installReselectHandling(on tabBarController: UITabBarController) {
            if let proxy = tabBarController.delegate as? ReselectProxy {
                proxy.onReselect = { [weak self] in self?.handleReselect() }
                return
            }
            let proxy = ReselectProxy(original: tabBarController.delegate)
            proxy.onReselect = { [weak self] in self?.handleReselect() }
            tabBarController.delegate = proxy
            objc_setAssociatedObject(tabBarController, &Self.proxyKey, proxy, .OBJC_ASSOCIATION_RETAIN_NONATOMIC)
        }

        private static var proxyKey: UInt8 = 0

        private func handleReselect() {
            if onReselect() { return }
            guard let root = tabBarController?.selectedViewController?.view,
                  let scrollView = Self.largestScrollView(in: root) else { return }
            let top = CGPoint(x: -scrollView.adjustedContentInset.left, y: -scrollView.adjustedContentInset.top)
            guard scrollView.contentOffset.y > top.y + 1 else { return }
            scrollView.setContentOffset(top, animated: true)
        }

        /// 页面里最大的那个滚动视图（排除横向的小货架）。
        private static func largestScrollView(in view: UIView) -> UIScrollView? {
            var best: (UIScrollView, CGFloat)?
            func visit(_ view: UIView) {
                if let scrollView = view as? UIScrollView, !scrollView.isHidden, scrollView.alpha > 0.01,
                   scrollView.contentSize.height > scrollView.bounds.height * 0.5 || scrollView.bounds.height > 300 {
                    let area = scrollView.bounds.width * scrollView.bounds.height
                    if area > (best?.1 ?? 0) { best = (scrollView, area) }
                }
                view.subviews.forEach(visit)
            }
            visit(view)
            return best?.0
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

/// 转发给 SwiftUI 原来的标签栏代理，只在再次点按已选中的标签时多通知一次。
private final class ReselectProxy: NSObject, UITabBarControllerDelegate {
    private weak var original: UITabBarControllerDelegate?
    var onReselect: () -> Void = {}

    init(original: UITabBarControllerDelegate?) {
        self.original = original
    }

    func tabBarController(_ tabBarController: UITabBarController, shouldSelectTab tab: UITab) -> Bool {
        if tab === tabBarController.selectedTab { onReselect() }
        return original?.tabBarController?(tabBarController, shouldSelectTab: tab) ?? true
    }

    func tabBarController(_ tabBarController: UITabBarController, didSelectTab selectedTab: UITab, previousTab: UITab?) {
        original?.tabBarController?(tabBarController, didSelectTab: selectedTab, previousTab: previousTab)
    }

    override func responds(to selector: Selector!) -> Bool {
        super.responds(to: selector) || (original?.responds(to: selector) ?? false)
    }

    override func forwardingTarget(for selector: Selector!) -> Any? {
        original?.responds(to: selector) == true ? original : super.forwardingTarget(for: selector)
    }
}
