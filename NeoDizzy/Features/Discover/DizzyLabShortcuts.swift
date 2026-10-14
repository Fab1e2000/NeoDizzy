import SwiftUI

struct DizzyLabShortcuts: View {
    @Environment(PlayerStore.self) private var player
    @Environment(NowPlayingPresentation.self) private var nowPlaying
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
        LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 12),
                                 count: dynamicTypeSize.isAccessibilitySize ? 1 : 2), spacing: 12) {
            ForEach(DizzyLabSection.allCases) { section in
                if section == .shuffle {
                    DiscoveryShortcutButton(title: section.title, systemImage: section.systemImage) {
                        let selection = try await DizzyCommunity.shared.shuffle()
                        try Task.checkCancellation()
                        player.playDiscovery(selection)
                        nowPlaying.isPresented = true
                    }
                } else {
                NavigationLink(value: AppRoute.dizzyLab(section)) {
                    ModuleShortcutCard(title: section.title, systemImage: section.systemImage)
                }
                .buttonStyle(.plain)
                .accessibilityLabel(section.title)
                }
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("DizzyLab 功能")
    }
}
