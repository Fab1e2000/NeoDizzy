import AppKit
import QuartzCore
import SwiftUI

/// 主窗口：工具栏正中是顶部导航栏，内容区底部是播放条，右侧是歌词 / 待播清单面板。
/// 面板是内容区旁边的普通视图而不是 `.inspector`：系统检查器在工具栏放得下时会改成通到窗口顶部的样式，
/// 窄窗口里工具栏只剩左半段，与宽窗口的样子不一致。
/// 不使用侧边栏，主导航参考 Petrichor：工具栏中间一组分段按钮切换页面；搜索是导航栏里的一个页面。
struct MainWindow: View {
    @Environment(MacAppModel.self) private var model
    @Environment(AccountStore.self) private var account
    @Environment(\.openWindow) private var openWindow
    @Environment(\.openSettings) private var openSettings
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var window: NSWindow?
    @State private var windowWidth: CGFloat = 1180
    @State private var navigationFullWidth: CGFloat = 700
    // 请求状态与实际展示分开：先完成窗口加宽动画，再让面板占用布局空间。
    @State private var isPanelPresented = false
    @AppStorage("playerPanel.width") private var panelWidth: Double = 300
    @State private var windowResizeTask: Task<Void, Never>?
    @State private var windowResizeID: UUID?

    var body: some View {
        @Bindable var model = model
        @Bindable var account = account
        HStack(spacing: 0) {
            DetailColumn()
                .background(alignment: .topLeading) { NavigationBarWidthReader(width: $navigationFullWidth) }
            if isPanelPresented {
                PanelResizeHandle(width: $panelWidth)
                PlayerInspector()
                    .frame(width: panelWidth)
                    // 背景不延伸到工具栏后面：工具栏保持横跨整个窗口的一条，面板从它下面开始。
                    .background(.background.secondary, ignoresSafeAreaEdges: .bottom)
                    .transition(.move(edge: .trailing))
            }
        }
        .toolbar {
            ToolbarItem(placement: .principal) {
                TopNavigationBar(window: window, windowWidth: windowWidth, fullWidth: navigationFullWidth)
            }
        }
        // 页面标题写在内容里，工具栏只放导航，与 Music 一致。
        .toolbar(removing: .title)
        .sheet(item: $model.purchaseTarget) { PurchaseSheet(summary: $0) }
        .sheet(isPresented: $account.isLoginPresented) { LoginSheet() }
        .sheet(isPresented: $model.isDisclaimerPresented) { DisclaimerSheet() }
        // 面板打开时内容区仍要放得下播放条三栏，窗口不能再缩到只剩面板宽度。
        .frame(minWidth: isPanelPresented ? max(720, Self.minimumContentWidth + panelWidth) : 720, minHeight: 560)
        .background(WindowReader(window: $window))
        // 窗口缩放通知早于工具栏排版，按钮先换成图标再参与排版，不会被整组收进溢出菜单。
        .onReceive(NotificationCenter.default.publisher(for: NSWindow.didResizeNotification, object: window)) { _ in
            if let window { windowWidth = window.frame.width }
        }
        .onChange(of: window, initial: true) { _, window in
            if let window { windowWidth = window.frame.width }
        }
        .task(id: PanelPresentationRequest(isOpen: model.playerPanel != nil, windowNumber: window?.windowNumber)) {
            await updatePanelPresentation()
        }
        .onAppear {
            let openWindow = openWindow, openSettings = openSettings
            model.openWindow = { openWindow(id: $0) }
            model.openSettings = { openSettings() }
        }
    }

    private struct PanelPresentationRequest: Equatable {
        let isOpen: Bool
        let windowNumber: Int?
    }

    @MainActor
    private func updatePanelPresentation() async {
        guard model.playerPanel != nil else {
            withAnimation(reduceMotion ? nil : .smooth(duration: 0.22)) {
                isPanelPresented = false
            }
            return
        }
        guard let window, !isPanelPresented else { return }
        await widenWindowForPanel(window)
        // 快速关闭/重开或窗口销毁时，旧动画的完成回调不能再次展开面板。
        guard !Task.isCancelled, model.playerPanel != nil else { return }
        withAnimation(reduceMotion ? nil : .smooth(duration: 0.25)) {
            isPanelPresented = true
        }
    }

    /// 窄窗口先平滑加宽，完成后才展示面板，避免两个布局变化同时争抢空间。
    @MainActor
    private func widenWindowForPanel(_ window: NSWindow) async {
        // 关闭请求不回缩已开始的窗口动画；快速重开必须等待它结束，不能抢先展示或叠加动画。
        if let resize = windowResizeTask { await resize.value }
        guard !Task.isCancelled,
              !window.styleMask.contains(.fullScreen), let screen = window.screen?.visibleFrame else { return }
        let needed = Self.minimumContentWidth + panelWidth
        let targetWidth = min(needed, screen.width)
        // 屏幕容不下目标宽度时也不缩小原窗口；全屏与足够宽的窗口直接展开面板。
        guard window.frame.width + 1 < targetWidth else { return }
        var frame = window.frame
        frame.size.width = targetWidth
        // 优先向右加宽，碰到屏幕右边缘时整体左移。
        frame.origin.x = max(screen.minX, min(frame.origin.x, screen.maxX - frame.width))
        if reduceMotion {
            window.setFrame(frame, display: true)
            return
        }
        let resizeID = UUID()
        let resize = Task { @MainActor in
            await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
                NSAnimationContext.runAnimationGroup { context in
                    context.duration = 0.32
                    context.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
                    window.animator().setFrame(frame, display: true)
                } completionHandler: {
                    continuation.resume()
                }
            }
        }
        windowResizeID = resizeID
        windowResizeTask = resize
        await resize.value
        if windowResizeID == resizeID {
            windowResizeTask = nil
            windowResizeID = nil
        }
    }

    private static let minimumContentWidth: CGFloat = 560
}

enum NavigationDisplayMode: String, CaseIterable {
    case iconOnly, titleOnly, titleAndIcon

    var title: String {
        switch self {
        case .iconOnly: String(localized: "图标")
        case .titleOnly: String(localized: "文本")
        case .titleAndIcon: String(localized: "图标和文本")
        }
    }
}

/// 顶部导航栏：工具栏正中的一组分段按钮，参考 Petrichor 的 TabbedButtons。
/// 选中背景在按钮之间滑动；空间不够时只显示图标，悬停显示名称。再次点击当前项回到它的根页面。
///
/// 工具栏只按视图的理想宽度摆放，不会替我们挑选更窄的样式（ViewThatFits 在这里无效）：
/// 居中后压到左侧红绿灯或右侧按钮时，AppKit 会把整组按钮收起。所以按窗口宽度自己决定，
/// 两侧各留 150 点给红绿灯、返回按钮和页面自己的工具栏按钮。
struct TopNavigationBar: View {
    let window: NSWindow?
    let windowWidth: CGFloat
    /// 带文字时整组的宽度，由 `NavigationBarWidthReader` 在工具栏之外测量。
    let fullWidth: CGFloat
    @Environment(MacAppModel.self) private var model
    @Environment(TabSettings.self) private var tabs
    @AppStorage("navigation.displayMode") private var displayMode = NavigationDisplayMode.titleAndIcon

    var body: some View {
        let isCompact = windowWidth < fullWidth + 300
        NavigationButtons(isCompact: isCompact)
            // 工具栏项变宽或变窄、或页面重建工具栏项后，AppKit 不会自己重新计算哪些项放得下：
            // 已经收进溢出菜单的整组按钮换成图标后仍然藏着。SwiftUI 更新工具栏项的时机不固定，
            // 所以在这些时刻之后分几次让标题栏重新布局；拖动缩放结束时再补一次。
            .onChange(of: isCompact) { window?.scheduleToolbarRelayout() }
            .onChange(of: displayMode) { window?.scheduleToolbarRelayout() }
            .onReceive(NotificationCenter.default.publisher(for: NSToolbar.willAddItemNotification, object: window?.toolbar)) { _ in
                window?.scheduleToolbarRelayout()
            }
            .onReceive(NotificationCenter.default.publisher(for: NSWindow.didEndLiveResizeNotification, object: window)) { _ in
                window?.scheduleToolbarRelayout()
            }
            .onChange(of: tabs.visibleTabs) { _, visible in
                let navigation = model.navigation
                if case .tab(let tab)? = navigation.selection, !visible.contains(tab) {
                    navigation.selection = visible.first.map(NavigationItem.tab) ?? .history
                }
            }
    }
}

extension NSWindow {
    /// 工具栏项的宽度变化或被重建后，AppKit 不会自己重新计算哪些项放得下。
    /// SwiftUI 更新的时机不固定，分几次让标题栏重新布局。
    func scheduleToolbarRelayout() {
        for delay in [0, 0.1, 0.35] {
            DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak self] in self?.relayoutToolbar() }
        }
    }

    private func relayoutToolbar() {
        guard let frameView = contentView?.superview else { return }
        for item in toolbar?.items ?? [] {
            item.view?.invalidateIntrinsicContentSize()
            item.view?.needsLayout = true
        }
        frameView.needsLayout = true
        frameView.layoutSubtreeIfNeeded()
    }
}

/// 在内容区里不可见地摆一份带文字的导航栏，量出它的宽度。
/// 不能放在工具栏项里：工具栏按整个视图的 fittingSize 定宽，测量副本会让它按完整宽度占位。
struct NavigationBarWidthReader: View {
    @Binding var width: CGFloat

    var body: some View {
        NavigationButtons(isCompact: false, isMeasuring: true)
            .fixedSize()
            .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { width = $0 }
            .hidden()
            .frame(width: 0, height: 0)
            .allowsHitTesting(false)
            .accessibilityHidden(true)
    }
}

private struct NavigationButtons: View {
    let isCompact: Bool
    var isMeasuring = false
    @Environment(MacAppModel.self) private var model
    @Environment(TabSettings.self) private var tabs
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @AppStorage("navigation.displayMode") private var displayMode = NavigationDisplayMode.titleAndIcon
    @Namespace private var selectionNamespace

    private var items: [NavigationItem] { [.search] + tabs.visiblePrimary.map(NavigationItem.tab) + [.history] }

    var body: some View {
        let navigation = model.navigation
        HStack(spacing: 2) {
            ForEach(items, id: \.self) { item in
                TopNavigationButton(item: item, isSelected: navigation.selection == item, displayMode: isCompact ? .iconOnly : displayMode,
                                    namespace: selectionNamespace, allowsContextMenu: !isMeasuring) {
                    if navigation.selection == item {
                        navigation.popToRoot(item)
                    } else {
                        navigation.selection = item
                    }
                }
            }
        }
        .padding(3)
        // 动画只作用于导航栏本身，页面切换不跟着做过渡动画。
        .animation(reduceMotion ? nil : .snappy(duration: 0.25), value: navigation.selection)
    }
}

private struct TopNavigationButton: View {
    let item: NavigationItem
    let isSelected: Bool
    let displayMode: NavigationDisplayMode
    let namespace: Namespace.ID
    let allowsContextMenu: Bool
    let action: () -> Void
    @Environment(TabSettings.self) private var tabs
    @Environment(\.openSettings) private var openSettings
    @State private var isHovering = false
    @AppStorage("navigation.displayMode") private var preferredDisplayMode = NavigationDisplayMode.titleAndIcon

    var body: some View {
        Button(action: action) {
            HStack(spacing: 5) {
                if displayMode != .titleOnly { Image(systemName: item.systemImage) }
                if displayMode != .iconOnly { Text(item.title) }
            }
                .font(.system(size: 13, weight: isSelected ? .semibold : .medium))
                .foregroundStyle(isSelected ? AnyShapeStyle(Color.dizzyAccent) : AnyShapeStyle(.secondary))
                .fixedSize()
                .padding(.horizontal, displayMode == .iconOnly ? 9 : 12)
                .frame(height: 28)
                .background {
                    if isSelected {
                        Capsule()
                            .fill(Color.dizzyAccent.opacity(0.2))
                            .matchedGeometryEffect(id: "selection", in: namespace)
                    } else if isHovering {
                        Capsule().fill(.primary.opacity(0.07))
                    }
                }
                .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .onHover { isHovering = $0 }
        .help(item.title)
        .accessibilityLabel(item.title)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
        .overlay {
            if allowsContextMenu {
                NavigationContextMenu(mode: $preferredDisplayMode, item: item, tabs: tabs, openSettings: { openSettings() })
            }
        }
    }
}

/// 工具栏会吞掉 SwiftUI contextMenu；只拦截右键，普通点击仍交给 SwiftUI 按钮。
private struct NavigationContextMenu: NSViewRepresentable {
    @Binding var mode: NavigationDisplayMode
    let item: NavigationItem
    let tabs: TabSettings
    let openSettings: () -> Void

    func makeNSView(context: Context) -> MenuView {
        let view = MenuView()
        view.startMonitoring()
        return view
    }

    static func dismantleNSView(_ view: MenuView, coordinator: ()) { view.stopMonitoring() }

    func updateNSView(_ view: MenuView, context: Context) {
        view.options = NavigationDisplayMode.allCases.map { option in
            (option.title, mode == option, true, { mode = option })
        }
        if case .tab(let tab) = item {
            view.options.append((String(localized: "从导航栏隐藏「\(tab.title)」"), false, tabs.canHide(tab), {
                tabs.setVisible(false, for: tab)
            }))
        }
        view.options.append((String(localized: "编辑导航栏…"), false, true, openSettings))
    }

    final class MenuView: NSView {
        var options: [(title: String, checked: Bool, enabled: Bool, action: () -> Void)] = []

        private var eventMonitor: Any?

        func startMonitoring() {
            eventMonitor = NSEvent.addLocalMonitorForEvents(matching: [.rightMouseDown, .leftMouseDown]) { [weak self] event in
                guard let self, event.window === self.window, !self.isHiddenOrHasHiddenAncestor,
                      event.type == .rightMouseDown || event.modifierFlags.contains(.control),
                      self.bounds.contains(self.convert(event.locationInWindow, from: nil)) else { return event }
                self.showMenu(event)
                return nil
            }
        }

        func stopMonitoring() {
            if let eventMonitor { NSEvent.removeMonitor(eventMonitor) }
            eventMonitor = nil
        }

        // 不参与命中测试，左键、悬停和辅助功能继续由下面的按钮处理。
        override func hitTest(_ point: NSPoint) -> NSView? { nil }

        private func showMenu(_ event: NSEvent) {
            let menu = NSMenu()
            menu.autoenablesItems = false
            for (index, option) in options.enumerated() {
                if index == NavigationDisplayMode.allCases.count { menu.addItem(.separator()) }
                let entry = NSMenuItem(title: option.title, action: #selector(selectOption(_:)), keyEquivalent: "")
                entry.tag = index
                entry.target = self
                entry.state = option.checked ? .on : .off
                entry.isEnabled = option.enabled
                menu.addItem(entry)
            }
            NSMenu.popUpContextMenu(menu, with: event, for: self)
        }

        @objc private func selectOption(_ sender: NSMenuItem) {
            guard options.indices.contains(sender.tag) else { return }
            options[sender.tag].action()
        }
    }
}

/// 内容区：每个导航项一个导航栈，路径保存在 `NavigationModel` 里，切换后再回来仍停在原页面。
struct DetailColumn: View {
    @Environment(MacAppModel.self) private var model

    var body: some View {
        let navigation = model.navigation
        let item = navigation.selection ?? .tab(.discover)
        NavigationStack(path: Binding(get: { navigation.path(for: item) }, set: { navigation.setPath($0, for: item) })) {
            RootPage(item: item)
                .environment(\.pageScrollKey, item)
                .detailChrome()
                .navigationDestination(for: AppRoute.self) { RouteDestination(route: $0).detailChrome() }
        }
        .id(item)
    }
}

private struct RootPage: View {
    let item: NavigationItem

    var body: some View {
        switch item {
        case .search: SearchPage()
        case .tab(.discover): DiscoverPage()
        case .tab(.shuffle): ShufflePage()
        case .tab(.labels): LabelsPage()
        case .tab(.feed): FeedPage()
        case .tab(.purchased): PurchasedPage()
        case .tab(.localLibrary): LocalLibraryPage()
        case .history: HistoryPage()
        }
    }
}

/// 导航栈里可以推入的页面，对应 iOS 的 AppRouteDestination。
struct RouteDestination: View {
    let route: AppRoute

    var body: some View {
        switch route {
        case .disc(let id): AlbumPage(id: id)
        case .localAlbum(let id): LocalAlbumPage(id: id)
        case .label(let name): LabelDetailPage(name: name)
        case .user(let id): UserPage(userID: id)
        case .tag(let tag): TagPage(tag: tag)
        case .pack(let id): PackPage(id: id)
        case .review(let id): ReviewPage(id: id)
        // Mac 的专辑页里已经完整展示社区内容。
        case .discCommunity(let id): AlbumPage(id: id)
        }
    }
}

extension View {
    /// 内容区每个页面共有的普通底部播放条，由页面自身布局，不覆盖主窗口。
    /// 根页与推入页使用同一结构：macOS 会替换整个详情栏，栈外的修饰符不会保留。
    func detailChrome() -> some View {
        modifier(DetailChrome())
    }

    /// 登记当前页面的刷新动作，供「显示 → 刷新」（⌘R）调用。
    func pageRefresh(_ action: @escaping () async -> Void) -> some View {
        modifier(PageRefreshModifier(action: action))
    }
}

private struct PageRefreshModifier: ViewModifier {
    @Environment(MacAppModel.self) private var model
    @State private var id = UUID()
    let action: () async -> Void

    func body(content: Content) -> some View {
        content
            .onAppear { model.registerRefresh(PageRefresh(id: id, action: action)) }
            .onDisappear { model.unregisterRefresh(id) }
    }
}

/// 播放条就是详情页的底部区域，随详情栏自然伸缩；播放状态由共享 PlayerStore 持有。
private struct DetailChrome: ViewModifier {
    func body(content: Content) -> some View {
        content
            .safeAreaInset(edge: .bottom, spacing: 0) {
                PlayerBar()
            }
            // 页面内容的最小宽度不反馈给窗口：否则窄窗口里内容与面板互相调整尺寸，
            // 会触发 AppKit 的约束更新循环。
            .frame(minWidth: 0, idealWidth: 0, maxWidth: .infinity, maxHeight: .infinity)
    }
}

/// 面板左侧的分隔线，拖动调整面板宽度。
private struct PanelResizeHandle: View {
    @Binding var width: Double
    @State private var startWidth: Double?

    var body: some View {
        Rectangle()
            .fill(.separator)
            .frame(width: 1)
            .overlay {
                Color.clear
                    .frame(width: 9)
                    .contentShape(.rect)
                    // 由系统管理指针：面板在悬停时被关闭也不会留下错误的指针。
                    .pointerStyle(.columnResize)
                    .gesture(
                        DragGesture(minimumDistance: 1, coordinateSpace: .global)
                            .onChanged { value in
                                let start = startWidth ?? width
                                startWidth = start
                                width = min(420, max(260, start - value.translation.width))
                            }
                            .onEnded { _ in startWidth = nil }
                    )
            }
            .accessibilityHidden(true)
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
