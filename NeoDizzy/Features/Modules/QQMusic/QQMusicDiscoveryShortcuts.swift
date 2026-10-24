import SwiftUI

struct QQMusicDiscoveryShortcuts: View {
    @Environment(QQMusicStore.self) private var store
    @Environment(PlayerStore.self) private var player
    @Environment(NowPlayingPresentation.self) private var nowPlaying
    @Environment(\.dynamicTypeSize) private var typeSize

    var body: some View {
        let layout = typeSize.isAccessibilitySize
            ? AnyLayout(VStackLayout(spacing: 12))
            : AnyLayout(HStackLayout(alignment: .top, spacing: 12))
        GlassEffectContainer(spacing: 12) {
            layout {
                DiscoveryShortcutButton(title: "猜你喜欢") { starting in
                    FeaturedShortcutCard(title: "猜你喜欢", subtitle: "随心听，遇见下一首",
                                         icon: .symbol("dot.radiowaves.left.and.right"), startsPlayback: true, isLoading: starting)
                } start: {
                    guard store.active else { throw CancellationError() }
                    guard store.credential != nil else { store.showsAccount = true; return }
                    let revision = store.revision
                    let playbackIntent = player.playbackIntentRevision
                    let first = try await store.radio.start()
                    try Task.checkCancellation()
                    guard store.active, store.revision == revision,
                          player.playbackIntentRevision == playbackIntent else { throw CancellationError() }
                    player.playRemoteDiscovery(first, providerID: "qqmusic")
                    nowPlaying.isPresented = true
                }
                NavigationLink(value: AppRoute.qqmusic(.daily)) {
                    FeaturedShortcutCard(title: "每日30首", subtitle: "每天更新，为你挑选", icon: .today)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("每日30首")
            }
        }
    }
}
