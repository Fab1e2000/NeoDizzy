// Direct source port from MeloX (GPL-3.0), b8bc60f.
// NeoDizzy adapters are limited to track data, available playback features and localization.
import SwiftUI

struct HeartModeNowPlayingBadge: View {
    @Environment(PlayerStore.self) private var player

    @State private var showsActions = false

    var body: some View {
        if player.isHeartMode {
            Button {
                showsActions = true
            } label: {
                Label("心动模式", systemImage: "heart.fill")
                    .font(.caption2.weight(.semibold))
                    .lineLimit(1)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 5)
                    .foregroundStyle(.white)
                    .background(.white.opacity(0.14), in: .capsule)
            }
            .buttonStyle(.plain)
            .fixedSize()
            .accessibilityLabel("心动模式已开启")
            .accessibilityHint("管理心动模式")
            .confirmationDialog(
                "心动模式",
                isPresented: $showsActions,
                titleVisibility: .visible
            ) {
                Button(role: .destructive) {
                    player.disableHeartMode()
                } label: {
                    Label("退出心动模式", systemImage: "heart.slash")
                }

                Button("取消", role: .cancel) {}
            } message: {
                Text("退出后继续播放当前队列。")
            }
        }
    }
}
