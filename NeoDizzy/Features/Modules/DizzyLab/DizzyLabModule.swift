import SwiftUI

final class DizzyLabModule: AppModule {
    static var metadata: ModuleDescriptor {
        ModuleDescriptor(id: .dizzyLab, title: "DizzyLab", systemImage: "opticaldisc.fill",
                         accent: accent, imageAsset: "DizzyLabTabIcon")
    }
    /// DizzyLab 官网的金色；金底太亮，实底上配深棕字。
    static let accent = AccentPalette(light: 0xF0AD4E, dark: 0xF0AD4E, lightFill: 0xF0AD4E, darkFill: 0xF0AD4E,
                                      lightInk: 0x3D2600, darkInk: 0x3D2600)
    var descriptor: ModuleDescriptor { Self.metadata }
    var libraryOrigin: LibraryOrigin { .dizzylab }
    var downloadsWholeAlbums: Bool { true }
    var accountEntry: ModuleAccountEntry? {
        ModuleAccountEntry(title: "DizzyLab", avatarURL: DizzyURL.avatar(services.account.account?.avatarURL),
                           isSignedIn: services.account.account != nil)
    }
    func openAccount() {
        if services.account.account == nil {
            services.account.isLoginPresented = true
        } else {
            presentation.isAccountPresented = true
        }
    }
    func dismissAccount() {
        presentation.isAccountPresented = false
        services.account.isLoginPresented = false
    }
    private let contentCache = DizzyLabContentCache()
    let services: DizzyLabServices
    private let presentation = DizzyLabPresentation()

    private let onAccountChange: () -> Void
    private let onLibraryChange: () -> Void
    init(services: DizzyLabServices, onAccountChange: @escaping () -> Void = {}, onLibraryChange: @escaping () -> Void = {}) {
        self.services = services; self.onAccountChange = onAccountChange; self.onLibraryChange = onLibraryChange
    }
    func songAlbumRoute(for track: Track) -> AppRoute? {
        guard !track.discID.isEmpty else { return nil }
        return .disc(id: track.discID)
    }
    func collectionRoute(kind: String, itemID: String) -> AppRoute? {
        kind == "album" ? .disc(id: itemID) : nil
    }
    /// 这个来源只有社团页，没有艺人页：点作者名直接进入专辑所属的社团。
    var artistNavigation: PlayerArtistNavigation { .single }
    func artistDestinations(for track: Track) async throws -> [PlayerArtistDestination] {
        // 歌曲的来源标识是 libraryOrigin（"dizzylab"），和模块 ID（"dizzyLab"）大小写不同。
        guard track.playbackProviderID == libraryOrigin.rawValue else { return [] }
        let label = try await DizzyAPI.shared.discDetail(id: track.discID).summary.labelName
        try Task.checkCancellation()
        // This source exposes label pages, not individual performer pages.
        return label.map { [PlayerArtistDestination(name: $0, route: .label(name: $0))] } ?? []
    }
    func deactivate() { contentCache.stop() }
    func rootView() -> AnyView { AnyView(DiscoverView()) }
    func searchSection(query: String) -> AnyView? { AnyView(DizzyLabSearchSection(query: query)) }
    func destination(for route: AppRoute) -> AnyView? {
        guard route.moduleID == descriptor.id, let destination = route.destination.base as? DizzyLabRoute else { return nil }
        return AnyView(DizzyLabDestination(route: destination))
    }
    func install(in content: AnyView) -> AnyView {
        AnyView(DizzyLabScope(services: services, presentation: presentation, content: content, onAccountChange: onAccountChange, onLibraryChange: onLibraryChange).environment(contentCache))
    }
    func handleURL(_ url: URL, host: ModuleHost) -> Bool {
        guard AlipayReturnRouter.isCallback(url) else { return false }
        dismissAccount()
        // A callback only resumes authoritative server-side order verification.
        host.dismissPresentations = true
        if !host.select(descriptor.id, path: [.dizzyLab(.purchased)]), let pending = services.purchases.current {
            presentation.paymentSheet = PurchaseSheet(summary: DiscSummary(id: pending.attempt.discID, title: pending.title, coverURL: nil))
        }
        NotificationCenter.default.post(name: .dizzyPaymentReturned, object: nil)
        Task { await services.purchases.check() }
        return true
    }
}

@Observable
private final class DizzyLabPresentation {
    var paymentSheet: PurchaseSheet?
    var isAccountPresented = false
}

private struct DizzyLabScope: View {
    let services: DizzyLabServices
    @Bindable var presentation: DizzyLabPresentation
    let content: AnyView
    let onAccountChange: () -> Void
    let onLibraryChange: () -> Void
    @Environment(\.scenePhase) private var scenePhase
    @Environment(DizzyLabContentCache.self) private var contentCache

    var body: some View {
        @Bindable var account = services.account
        content
            .sheet(isPresented: $presentation.isAccountPresented, onDismiss: { account.isLoginPresented = false }) {
                DizzyLabAccountView()
                    .sheet(isPresented: $account.isLoginPresented) { loginSheet }
            }
            .sheet(item: $presentation.paymentSheet) { PurchaseView(summary: $0.summary) }
            .sheet(isPresented: Binding(
                get: { account.isLoginPresented && !presentation.isAccountPresented },
                set: { if !$0 && !presentation.isAccountPresented { account.isLoginPresented = false } }
            )) { loginSheet }
            .environment(services.account)
            .environment(services.purchases)
            .onChange(of: scenePhase, initial: true) { _, phase in
                if phase == .background { services.purchases.pause() }
                if phase == .active { Task { await services.purchases.check() } }
            }
            .onReceive(NotificationCenter.default.publisher(for: .dizzyPurchaseDidComplete)) { _ in
                contentCache.purchasesChanged()
                onLibraryChange()
            }
            .onChange(of: account.account?.userID) { _, _ in onAccountChange() }
            .onReceive(NotificationCenter.default.publisher(for: .dizzyAccountDidChange)) { _ in
                contentCache.accountChanged()
                contentCache.prewarm(account: services.account)
                services.purchases.accountDidChange()
                Task { await services.purchases.check() }
            }
    }
    private var loginSheet: some View {
        NavigationStack {
            LoginView().toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(role: .close) { services.account.isLoginPresented = false }
                }
            }
        }
    }

}
