import SwiftUI

/// 独立的随机发现入口，只有用户点击后才请求并开始播放。
struct ShuffleView: View {
    let play: (ShuffleTrack) -> Void
    @State private var isRequesting = false
    @State private var failure: String?

    private var recordArtwork: some View {
        ZStack {
            Circle()
                .fill(RadialGradient(colors: [DizzyPalette.accent.opacity(0.24), .clear],
                                     center: .center, startRadius: 20, endRadius: 130))
            Circle()
                .fill(LinearGradient(colors: [Color(white: 0.23), Color(white: 0.07)],
                                     startPoint: .topLeading, endPoint: .bottomTrailing))
                .padding(20)
                .shadow(color: .black.opacity(0.3), radius: 16, y: 12)
            ForEach(0..<5) { ring in
                Circle().stroke(.white.opacity(0.07), lineWidth: 1)
                    .padding(CGFloat(30 + ring * 12))
            }
            Circle()
                .fill(DizzyPalette.accent.gradient)
                .frame(width: 82, height: 82)
            Image(systemName: "shuffle")
                .font(.system(size: 30, weight: .semibold))
                .foregroundStyle(DizzyPalette.onAccent)
        }
        .frame(maxWidth: 260)
        .aspectRatio(1, contentMode: .fit)
        .accessibilityHidden(true)
    }

    var body: some View {
        MainTabPage(tab: .shuffle) {
            VStack(spacing: 28) {
                recordArtwork
                    .padding(.top, 24)

                VStack(spacing: 10) {
                    Text("下一首，交给偶然")
                        .font(.title.bold())
                        .foregroundStyle(DizzyPalette.text)
                    Text("不必挑选，让一首音乐\n成为今天的小小发现。")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                        .lineSpacing(4)
                }

                Button {
                    failure = nil
                    isRequesting = true
                } label: {
                    HStack(spacing: 10) {
                        if isRequesting {
                            ProgressView().tint(DizzyPalette.onAccent)
                            Text("正在寻找下一首")
                        } else {
                            Label(failure == nil ? "开始随便听听" : "再试一次", systemImage: "shuffle")
                        }
                    }
                    .font(.headline)
                    .frame(maxWidth: .infinity, minHeight: 30)
                    .padding(.vertical, 4)
                }
                .buttonStyle(.borderedProminent)
                .buttonBorderShape(.capsule)
                .tint(DizzyPalette.accent)
                .foregroundStyle(DizzyPalette.onAccent)
                .controlSize(.large)
                .disabled(isRequesting)
                .padding(.horizontal, 16)

                if let failure {
                    VStack(spacing: 6) {
                        Label("暂时没能找到音乐", systemImage: "wifi.exclamationmark")
                            .font(.subheadline.weight(.medium))
                        Text(failure).font(.caption).foregroundStyle(.secondary)
                    }
                    .multilineTextAlignment(.center)
                    .accessibilityElement(children: .combine)
                } else {
                    Text("遇到喜欢的，就多听一会儿")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }
            .frame(maxWidth: 480)
            .frame(maxWidth: .infinity)
            .padding(.bottom, 32)
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
