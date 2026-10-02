import SwiftUI

/// 独立的随机发现入口，只有用户点击后才请求并开始播放。
struct ShuffleView: View {
    let play: (ShuffleTrack) -> Void
    @State private var isRequesting = false
    @State private var failure: String?

    var body: some View {
        MainTabPage(tab: .shuffle) {
            VStack(spacing: 20) {
                Image(systemName: "shuffle")
                    .font(.system(size: 64, weight: .light))
                    .foregroundStyle(DizzyPalette.accent)
                    .accessibilityHidden(true)
                Text("让下一首带来惊喜")
                    .font(.title2.bold())
                Text("随机发现一首音乐，找到后进入播放器。")
                    .font(.body)
                    .foregroundStyle(DizzyPalette.mutedText)
                    .multilineTextAlignment(.center)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 40)

            Button {
                failure = nil
                isRequesting = true
            } label: {
                HStack {
                    if isRequesting { ProgressView() }
                    Label(isRequesting ? "正在寻找…" : "随便听听", systemImage: "shuffle")
                }
                .frame(maxWidth: .infinity)
            }
            .buttonStyle(.bordered)
            .controlSize(.large)
            .disabled(isRequesting)
            if let failure {
                Text("获取歌曲失败：\(failure)\n点击「随便听听」重试。")
                    .font(.caption)
                    .foregroundStyle(DizzyPalette.mutedText)
            }
        }
        .task(id: isRequesting) {
            guard isRequesting else { return }
            defer { isRequesting = false }
            do {
                let selection = try await DizzyCommunity.shared.shuffle()
                try Task.checkCancellation()
                play(selection)
            } catch {
                if !Task.isCancelled { failure = error.localizedDescription }
            }
        }
    }
}
