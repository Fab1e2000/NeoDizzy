import SwiftUI

final class DizzyLabModule: AppModule {
    static var metadata: ModuleDescriptor {
        ModuleDescriptor(id: .dizzyLab, title: "DizzyLab", systemImage: "opticaldisc.fill")
    }
    var descriptor: ModuleDescriptor { Self.metadata }
    var accountEntry: ModuleAccountEntry? {
        ModuleAccountEntry(title: "DizzyLab", avatarURL: services.account.account?.avatarURL,
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

    init(services: DizzyLabServices) { self.services = services }
    func rootView() -> AnyView { AnyView(DiscoverView()) }
    func searchSection(query: String) -> AnyView? { AnyView(DizzyLabSearchSection(query: query)) }
    func destination(for route: AppRoute) -> AnyView? {
        guard route.moduleID == descriptor.id, let destination = route.destination.base as? DizzyLabRoute else { return nil }
        return AnyView(DizzyLabDestination(route: destination))
    }
    func install(in content: AnyView) -> AnyView {
        AnyView(DizzyLabScope(services: services, presentation: presentation, content: content).environment(contentCache))
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
            .environment(services.downloads)
            .environment(services.browsingHistory)
            .onChange(of: scenePhase, initial: true) { _, phase in
                if phase == .background { services.purchases.pause() }
                if phase == .active { Task { await services.purchases.check() } }
            }
            .onReceive(NotificationCenter.default.publisher(for: .dizzyPurchaseDidComplete)) { _ in
                contentCache.purchasesChanged()
            }
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
