import LNPopupUI
import Observation
import SwiftUI
import UIKit

/// System accessory views remain owned by SwiftUI. LN reads these actual rendered
/// views for its existing portal, material, artwork and interactive transitions.
@Observable @MainActor
final class PlayerTransitionState {
    @ObservationIgnored let externalSource = LNPopupExternalTransitionSource()
    var artwork: UIImage?

    /// Read the public accessory container after the real source enters a window.
    /// Its geometry is separate from the app-owned content mirrored by LN.
    func updateContainerView() {
        guard let content = externalSource.contentView,
              let window = content.window,
              let root = window.rootViewController else {
            externalSource.containerView = nil
            return
        }
        var pending = [root]
        var visited = Set<ObjectIdentifier>()
        while let controller = pending.popLast() {
            guard visited.insert(ObjectIdentifier(controller)).inserted else { continue }
            if let tab = controller as? UITabBarController,
               let container = tab.bottomAccessory?.contentView,
               container.window === window,
               content.isDescendant(of: container) {
                externalSource.containerView = container
                externalSource.cornerRadius = container.bounds.height / 2
                return
            }
            pending.append(contentsOf: controller.children)
            if let presented = controller.presentedViewController {
                pending.append(presented)
            }
        }
        externalSource.containerView = nil
    }
}

/// Thin SwiftUI/UIKit lifetime bridge. All visible transition choreography and
/// interactive drag behavior run through LNPopupController's original state machine.
struct NativePlayerPresentation<Content: View>: UIViewControllerRepresentable {
    @Binding var isPresented: Bool
    let state: PlayerTransitionState
    let onClose: () -> Void
    let content: Content

    init(isPresented: Binding<Bool>, state: PlayerTransitionState, onClose: @escaping () -> Void,
         @ViewBuilder content: () -> Content) {
        _isPresented = isPresented
        self.state = state
        self.onClose = onClose
        self.content = content()
    }

    func makeCoordinator() -> NativePlayerPresentationCoordinator {
        NativePlayerPresentationCoordinator(state: state)
    }

    func makeUIViewController(context: Context) -> NativePlayerPresenterController {
        let controller = NativePlayerPresenterController()
        context.coordinator.presenter = controller
        controller.onReady = { [weak coordinator = context.coordinator] in coordinator?.scheduleUpdate() }
        return controller
    }

    func updateUIViewController(_ controller: NativePlayerPresenterController, context: Context) {
        let coordinator = context.coordinator
        coordinator.isPresented = $isPresented
        coordinator.onClose = onClose
        coordinator.wantsPresentation = isPresented
        coordinator.reducesMotion = context.environment.accessibilityReduceMotion
        // UIKit hosting boundaries do not inherit the presenting SwiftUI environment.
        coordinator.content = AnyView(content.environment(\.self, context.environment))
        coordinator.presented?.updateContent(coordinator.content)
        coordinator.scheduleUpdate()
    }

    static func dismantleUIViewController(_ controller: NativePlayerPresenterController,
                                         coordinator: NativePlayerPresentationCoordinator) {
        controller.onReady = nil
        coordinator.wantsPresentation = false
        coordinator.presented?.requestClose(animated: false)
    }
}

final class NativePlayerPresenterController: UIViewController {
    var onReady: (() -> Void)?

    override func loadView() {
        view = UIView()
        view.backgroundColor = .clear
        view.isUserInteractionEnabled = false
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        onReady?()
    }
}

final class NativePlayerPresentationCoordinator {
    let state: PlayerTransitionState
    weak var presenter: NativePlayerPresenterController?
    var presented: NativePlayerContentController?
    var isPresented: Binding<Bool> = .constant(false)
    var onClose: () -> Void = {}
    var content = AnyView(EmptyView())
    var wantsPresentation = false
    var reducesMotion = false
    private var scheduled = false
    private weak var programmaticallyClosing: NativePlayerContentController?

    init(state: PlayerTransitionState) { self.state = state }

    func scheduleUpdate() {
        guard !scheduled else { return }
        scheduled = true
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            self.scheduled = false
            self.reconcile()
        }
    }

    private func reconcile() {
        guard let presenter, presenter.viewIfLoaded?.window != nil else { return }
        if wantsPresentation {
            guard presented == nil, presenter.presentedViewController == nil else { return }
            state.updateContainerView()
            let controller = NativePlayerContentController(content: content, state: state, reducesMotion: reducesMotion)
            controller.modalPresentationStyle = .overFullScreen
            controller.modalPresentationCapturesStatusBarAppearance = true
            controller.onClosed = { [weak self, weak controller] in
                guard let self, self.presented === controller else { return }
                // A new true binding supersedes a previously requested close.
                // Finish removing the old host, then honor the latest request.
                let shouldReopen = self.isPresented.wrappedValue && self.programmaticallyClosing === controller
                self.presented = nil
                self.programmaticallyClosing = nil
                if shouldReopen {
                    self.wantsPresentation = true
                    self.scheduleUpdate()
                    return
                }
                self.wantsPresentation = false
                self.isPresented.wrappedValue = false
                self.onClose()
            }
            presented = controller
            // UIKit adds only a transparent container. LN performs the visible open.
            presenter.present(controller, animated: false) { [weak self] in self?.scheduleUpdate() }
        } else {
            programmaticallyClosing = presented
            presented?.requestClose(animated: !reducesMotion)
        }
    }
}

/// A dedicated presentation host keeps LN's layout and runtime work isolated from
/// the real UITabBarController and its system accessory.
final class NativePlayerContentController: UIViewController, LNPopupPresentationDelegate {
    let hosting: LNPopupContentHostingController<AnyView>
    var onClosed: (() -> Void)?
    private let state: PlayerTransitionState
    private let reducesMotion: Bool
    private var content: AnyView
    private var viewportInsets: UIEdgeInsets = .zero
    private var viewportSize: CGSize = .zero
    private var installedPopup = false
    private var requestedClose = false
    private var requestedCloseAnimated = true
    private var removingOverlay = false
    private var deliveredClose = false
    private var dismissalCompletions: [() -> Void] = []
    private var isOpeningPopup = false
    private(set) var isClosingPopup = false
    private weak var pendingDismissalScrollView: UIScrollView?
    private weak var capturedDismissalScrollView: UIScrollView?
    private var capturedScrollWasEnabled = false
    private let transitionDiagnostics = PlayerTransitionDiagnostics()

    init(content: AnyView, state: PlayerTransitionState, reducesMotion: Bool) {
        self.content = content
        self.state = state
        self.reducesMotion = reducesMotion
        hosting = LNPopupContentHostingController(content: content)
        hosting.safeAreaRegions = []
        super.init(nibName: nil, bundle: nil)
        overrideUserInterfaceStyle = .dark
        hosting.overrideUserInterfaceStyle = .dark
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .clear
        view.accessibilityIdentifier = "player.fullscreen"
        view.accessibilityViewIsModal = true
        popupPresentationDelegate = self
        popupInteractionStyle = .automatic
        popupBar.externalTransitionSource = state.externalSource
        popupBar.barStyle = .floatingCompact
        popupContentView.popupCloseButtonStyle = .none
        popupContentView.overrideUserInterfaceStyle = .dark
        hosting.popupItem.image = state.artwork
        state.externalSource.interactionShouldBegin = { [weak self] pan in
            self?.canBeginInteraction(pan) ?? false
        }
        popupContentView.popupInteractionGestureRecognizer.addTarget(
            self, action: #selector(updateScrollOwnership(_:)))
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        if installedPopup {
            synchronizeStablePopupLayout()
        } else {
            configureViewport(size: view.bounds.size, insets: view.safeAreaInsets)
        }
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        guard !installedPopup, !removingOverlay else { return }
        if requestedClose {
            finishNativeDismissal()
            return
        }
        state.updateContainerView()
        configureViewport(size: view.bounds.size, insets: view.safeAreaInsets)
        transitionDiagnostics.begin("presentation_begin", host: self)
        installedPopup = true
        // Establish LN's closed state before opening, so its full artwork/content
        // transition runs rather than the hidden-to-open insertion fallback.
        presentPopupBar(with: hosting, openPopup: false, animated: false) { [weak self] in
            guard let self, !self.removingOverlay else { return }
            self.openPopup(animated: !self.reducesMotion)
            if self.requestedClose {
                self.closePopup(animated: self.requestedCloseAnimated)
            }
        }
    }

    override var preferredStatusBarStyle: UIStatusBarStyle { .lightContent }

    override func viewDidDisappear(_ animated: Bool) {
        super.viewDidDisappear(animated)
        transitionDiagnostics.finish("host_disappeared")
    }

    override var childForStatusBarHidden: UIViewController? { hosting }

    override func accessibilityPerformEscape() -> Bool {
        requestClose(animated: !reducesMotion)
        return true
    }

    /// External native dismissals still wait for LN's actual close before routing.
    override func dismiss(animated flag: Bool, completion: (() -> Void)? = nil) {
        if removingOverlay || presentedViewController != nil {
            super.dismiss(animated: flag, completion: completion)
            return
        }
        if let completion { dismissalCompletions.append(completion) }
        requestClose(animated: flag)
    }

    func updateContent(_ content: AnyView) {
        self.content = content
        updateHostedRoot()
        hosting.popupItem.image = state.artwork
    }

    private func configureViewport(size: CGSize, insets: UIEdgeInsets) {
        guard viewportSize != size || viewportInsets != insets else { return }
        viewportSize = size
        viewportInsets = insets
        updateHostedRoot()
    }

    private func synchronizeStablePopupLayout() {
        guard !removingOverlay, !isOpeningPopup, !isClosingPopup, !popupTransitionInProgress,
              popupPresentationState == .open || popupPresentationState == .barPresented else { return }
        let panState = popupContentView.popupInteractionGestureRecognizer.state
        guard panState != .began, panState != .changed,
              popupContentView.layer.animationKeys()?.isEmpty != false else { return }
        state.updateContainerView()
        let bounds = view.bounds
        // A routine layout pass must never restore y=0 while LN owns a drag or
        // its return animation. Only actual viewport changes need frame updates.
        guard viewportSize != bounds.size || viewportInsets != view.safeAreaInsets else { return }
        configureViewport(size: bounds.size, insets: view.safeAreaInsets)
        // Global LN layout interception is disabled for the system accessory path.
        // The ordinary host therefore updates its own LN subtree explicitly, only
        // after transitions and interactive settling have finished.
        UIView.performWithoutAnimation {
            if popupPresentationState == .open {
                if popupContentView.frame != bounds { popupContentView.frame = bounds }
            } else {
                var frame = popupContentView.frame
                frame.size = CGSize(width: bounds.width, height: 0)
                if popupContentView.frame != frame { popupContentView.frame = frame }
            }
            // LN inserts the hosting view directly in its content container.
            if let contentContainer = hosting.view.superview, contentContainer.frame != bounds {
                contentContainer.frame = bounds
            }
            if hosting.view.frame != bounds { hosting.view.frame = bounds }
        }
    }

    private func updateHostedRoot() {
        // The outer controller remains stationary; the LN content moves. Supply
        // stable safe-area values explicitly so dragging cannot relayout lyrics.
        hosting.popupContentRootView = AnyView(
            content
                .safeAreaInset(edge: .top, spacing: 0) {
                    Color.clear.frame(height: viewportInsets.top).allowsHitTesting(false)
                }
                .safeAreaInset(edge: .bottom, spacing: 0) {
                    Color.clear.frame(height: viewportInsets.bottom).allowsHitTesting(false)
                }
        )
    }

    func requestClose(animated: Bool) {
        guard !removingOverlay, !requestedClose else { return }
        transitionDiagnostics.begin("close_requested", host: self)
        requestedClose = true
        requestedCloseAnimated = animated
        guard installedPopup else { return }
        closePopup(animated: animated)
    }

    func popupPresentationController(_ popupPresentationController: UIViewController,
                                     willOpenPopupWithContentController popupContentController: UIViewController,
                                     animated: Bool) {
        isOpeningPopup = true
        isClosingPopup = false
        transitionDiagnostics.begin("will_open", host: self)
    }

    func popupPresentationController(_ popupPresentationController: UIViewController,
                                     didOpenPopupWithContentController popupContentController: UIViewController,
                                     animated: Bool) {
        isOpeningPopup = false
        isClosingPopup = false
        transitionDiagnostics.finish("did_open_or_return")
        view.setNeedsLayout()
        if requestedClose { closePopup(animated: requestedCloseAnimated) }
    }

    func popupPresentationController(_ popupPresentationController: UIViewController,
                                     willClosePopupWithContentController popupContentController: UIViewController,
                                     animated: Bool) {
        isClosingPopup = true
        transitionDiagnostics.begin("will_close", host: self)
        // Keep the backdrop in the live content portal for LN's closing fade.
    }

    func popupPresentationController(_ popupPresentationController: UIViewController,
                                     didClosePopupWithContentController popupContentController: UIViewController,
                                     animated: Bool) {
        isOpeningPopup = false
        isClosingPopup = false
        transitionDiagnostics.finish("did_close")
        finishNativeDismissal()
    }

    private func finishNativeDismissal() {
        guard !removingOverlay else { return }
        removingOverlay = true
        transitionDiagnostics.finish("overlay_removed")
        releaseScrollOwnership()
        state.externalSource.interactionShouldBegin = nil
        if installedPopup {
            dismissPopupBar(animated: false) { [weak self] in self?.removeNativeOverlay() }
        } else {
            removeNativeOverlay()
        }
    }

    private func removeNativeOverlay() {
        super.dismiss(animated: false) { [weak self] in
            guard let self, !self.deliveredClose else { return }
            self.deliveredClose = true
            self.onClosed?()
            let completions = self.dismissalCompletions
            self.dismissalCompletions.removeAll()
            completions.forEach { $0() }
        }
    }

    private func canBeginInteraction(_ pan: UIPanGestureRecognizer) -> Bool {
        guard !removingOverlay, !requestedClose, popupInteractionCanBegin,
              hosting.presentedViewController == nil, presentedViewController == nil else { return false }
        // Direction is resolved over the touch sequence by LN's pan, so an
        // uncertain first velocity sample cannot reject the entire gesture.
        // Keep the initial touched view: moving across a button boundary while
        // recognition is pending must not change the gesture's owner.
        var target = (pan as? LNPopupInteractionPanGestureRecognizer)?.initialTouchView
            ?? hosting.view.hitTest(pan.location(in: hosting.view), with: nil)
        var scrollAtTop: UIScrollView?
        while let candidate = target, candidate !== hosting.view {
            // Buttons retain taps; a recognised vertical drag cancels the tap.
            // Sliders and other continuous controls keep their editing gesture.
            if candidate is UIControl, !(candidate is UIButton) { return false }
            if let scroll = candidate as? UIScrollView, scroll.isScrollEnabled {
                guard scroll.contentOffset.y <= -scroll.adjustedContentInset.top + 1 else { return false }
                if scrollAtTop == nil { scrollAtTop = scroll }
            }
            target = candidate.superview
        }
        pendingDismissalScrollView = scrollAtTop
        return true
    }

    @objc private func updateScrollOwnership(_ pan: LNPopupInteractionPanGestureRecognizer) {
        if pan.state == .began {
            transitionDiagnostics.begin("pan_began", host: self)
        } else if pan.state == .ended {
            transitionDiagnostics.mark("pan_ended")
        } else if pan.state == .cancelled || pan.state == .failed {
            transitionDiagnostics.mark("pan_cancelled_or_failed")
        }
        switch pan.state {
        case .began, .changed:
            // Pending diagonal/horizontal movement still belongs to the list.
            // The LN handler is registered first and starts the real dismissal
            // only once the recognizer confirms downward intent.
            guard pan.externalVerticalIntentConfirmed, popupTransitionInProgress,
                  !popupInteractionCanBegin, !isClosingPopup else { return }
            if capturedDismissalScrollView == nil, let scroll = pendingDismissalScrollView {
                capturedDismissalScrollView = scroll
                capturedScrollWasEnabled = scroll.isScrollEnabled
                scroll.isScrollEnabled = false
            }
            if let scroll = capturedDismissalScrollView {
                scroll.setContentOffset(CGPoint(x: scroll.contentOffset.x,
                                              y: -scroll.adjustedContentInset.top), animated: false)
            }
        case .ended, .cancelled, .failed:
            releaseScrollOwnership()
        default:
            break
        }
    }

    private func releaseScrollOwnership() {
        if let scroll = capturedDismissalScrollView {
            scroll.isScrollEnabled = capturedScrollWasEnabled
        }
        capturedDismissalScrollView = nil
        pendingDismissalScrollView = nil
        capturedScrollWasEnabled = false
    }

}
