import SwiftUI
import UIKit

extension View {
    func gestureOnlyNavigation() -> some View {
        toolbar(.hidden, for: .navigationBar)
            .background(NativePopGestureAccess().frame(width: 0, height: 0))
    }
}

/// Preserve UIKit's recognizers and animation when the album omits its navigation bar.
/// This only restores gesture availability; UIKit handles direction and progress.
private struct NativePopGestureAccess: UIViewControllerRepresentable {
    func makeUIViewController(context: Context) -> Controller { Controller() }
    func updateUIViewController(_ controller: Controller, context: Context) {}
    static func dismantleUIViewController(_ controller: Controller, coordinator: ()) { controller.restore() }

    final class Controller: UIViewController {
        private var bindings: [(UIGestureRecognizer, (any UIGestureRecognizerDelegate)?, Bool)] = []
        override func viewDidAppear(_ animated: Bool) {
            super.viewDidAppear(animated)
            guard bindings.isEmpty, let navigationController, navigationController.viewControllers.count > 1 else { return }
            for gesture in [navigationController.interactivePopGestureRecognizer,
                            navigationController.interactiveContentPopGestureRecognizer].compactMap({ $0 }) {
                bindings.append((gesture, gesture.delegate, gesture.isEnabled))
                gesture.delegate = nil
                gesture.isEnabled = true
            }
        }
        override func viewDidDisappear(_ animated: Bool) {
            super.viewDidDisappear(animated)
            restore()
        }
        func restore() {
            for (gesture, original, enabled) in bindings where gesture.delegate == nil {
                gesture.delegate = original
                gesture.isEnabled = enabled
            }
            bindings.removeAll()
        }
    }
}
