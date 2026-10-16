import SwiftUI

struct DizzyLabShortcuts: View {
    @Environment(PlayerStore.self) private var player
    @Environment(NowPlayingPresentation.self) private var nowPlaying

    var body: some View {
        ModuleShortcutPanel {
            DiscoveryShortcutButton(title: DizzyLabSection.shuffle.title) { starting in
                ModulePrimaryShortcut(title: DizzyLabSection.shuffle.title, subtitle: "随机播放一首站内曲目",
                                      systemImage: DizzyLabSection.shuffle.systemImage, trailing: .play, isLoading: starting)
            } start: {
                let selection = try await DizzyCommunity.shared.shuffle()
                try Task.checkCancellation()
                player.playDiscovery(selection)
                nowPlaying.isPresented = true
            }
        } secondary: {
            ForEach(DizzyLabSection.allCases.filter { $0 != .shuffle }) { section in
                NavigationLink(value: AppRoute.dizzyLab(section)) {
                    ModuleSecondaryShortcut(title: section.title, systemImage: section.systemImage)
                }
                .buttonStyle(.plain)
                .accessibilityLabel(section.title)
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("DizzyLab 功能")
    }
}
