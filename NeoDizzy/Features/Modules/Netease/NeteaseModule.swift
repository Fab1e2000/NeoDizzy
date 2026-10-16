import SwiftUI

final class NeteaseModule: AppModule {
    static var metadata: ModuleDescriptor { .init(id: .netease, title: "网易云音乐", systemImage: "music.note") }
    var descriptor: ModuleDescriptor { Self.metadata }
    let store: NeteaseStore
    private let contentCache = NeteaseContentCache()
    init(store: NeteaseStore) { self.store = store }
    var accountEntry: ModuleAccountEntry? {
        .init(title: "网易云音乐", avatarURL: NeteaseArtwork.url(store.profile?.avatarUrl), isSignedIn: store.profile != nil)
    }
    func openAccount() { store.showsAccount = true }
    func dismissAccount() { store.showsAccount = false; store.showsLogin = false }
    func songActions(for track: Track, onImportLyrics: (() -> Void)?) -> AnyView? {
        guard track.remoteSource?.providerID == "netease" else { return nil }
        return AnyView(NeteasePlayerActions(track: track, onImportLyrics: onImportLyrics))
    }
    func rootView() -> AnyView { AnyView(NeteaseHomeView()) }
    func searchSection(query: String) -> AnyView? { AnyView(NeteaseSearchSection(query: query)) }
    func destination(for route: AppRoute) -> AnyView? {
        guard route.moduleID == .netease, let page = route.destination.base as? NeteaseRoute else { return nil }
        if case .artist(let id) = page { return AnyView(NeteaseArtistDetailView(id: id)) }
        if case .search(let query, let kind) = page { return AnyView(NeteaseSearchPage(query: query, kind: kind)) }
        return AnyView(NeteaseCollectionView(route: page))
    }
    func install(in content: AnyView) -> AnyView { AnyView(NeteaseScope(store: store, content: content).environment(contentCache)) }
}
private struct NeteaseScope: View {
    @Bindable var store: NeteaseStore
    let content: AnyView
    var body: some View {
        content
            .sheet(isPresented: $store.showsLogin) { NeteaseLoginView(store: store) }
            .sheet(isPresented: $store.showsAccount) {
                NeteaseSettingsView(store: store)
            }
            .environment(store)
    }
}
