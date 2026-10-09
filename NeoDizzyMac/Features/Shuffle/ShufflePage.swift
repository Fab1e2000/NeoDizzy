import SwiftUI

/// 随便听听：点击后获取一首随机曲目并播放；正在随便听听时展示当前曲目，可以继续请求下一首。
struct ShufflePage: View {
    @Environment(MacAppModel.self) private var model
    @Environment(PlayerStore.self) private var player
    @State private var isRequesting = false
    @State private var failure: String?

    var body: some View {
        ScrollView {
            VStack(spacing: 26) {
                if player.isDiscovery, let track = player.currentTrack {
                    current(track)
                } else {
                    record
                    VStack(spacing: 8) {
                        Text("下一首，交给偶然").font(.pageTitle)
                        Text("不必挑选，让一首音乐成为今天的小小发现。")
                            .font(.title3)
                            .foregroundStyle(.secondary)
                    }
                }
                requestButton
                if let failure {
                    Label(failure, systemImage: "wifi.exclamationmark")
                        .foregroundStyle(.secondary)
                } else if !player.isDiscovery {
                    Text("遇到喜欢的，就多听一会儿").foregroundStyle(.secondary)
                }
            }
            .frame(maxWidth: 520)
            .frame(maxWidth: .infinity)
            .padding(.horizontal, PageMetrics.margin)
            .padding(.vertical, 40)
        }
        .navigationTitle("随便听听")
        .task(id: isRequesting) {
            guard isRequesting else { return }
            defer { isRequesting = false }
            do {
                let selection = try await DizzyCommunity.shared.shuffle()
                try Task.checkCancellation()
                model.playDiscovery(selection)
            } catch {
                if !Task.isCancelled { failure = error.localizedDescription }
            }
        }
    }

    private var record: some View {
        ZStack {
            Circle()
                .fill(RadialGradient(colors: [Color.dizzyAccent.opacity(0.28), .clear], center: .center, startRadius: 30, endRadius: 150))
            Circle()
                .fill(LinearGradient(colors: [Color(white: 0.24), Color(white: 0.06)], startPoint: .topLeading, endPoint: .bottomTrailing))
                .padding(24)
                .shadow(color: .black.opacity(0.3), radius: 16, y: 12)
            ForEach(0..<5) { ring in
                Circle().stroke(.white.opacity(0.07), lineWidth: 1).padding(CGFloat(36 + ring * 13))
            }
            Circle().fill(DizzyPalette.accent.gradient).frame(width: 90, height: 90)
            Image(systemName: "shuffle").font(.system(size: 32, weight: .semibold)).foregroundStyle(.black)
        }
        .frame(width: 280, height: 280)
        .accessibilityHidden(true)
    }

    private func current(_ track: Track) -> some View {
        VStack(spacing: 14) {
            ArtworkImage(url: track.coverURL, cornerRadius: 12, decodeSize: AlbumArtworkSize.hero)
                .frame(width: 280)
                .shadow(color: .black.opacity(0.22), radius: 16, y: 10)
            VStack(spacing: 4) {
                Text(track.title).font(.title2.bold()).multilineTextAlignment(.center)
                Text(track.artists).font(.title3).foregroundStyle(.secondary)
                Button(track.albumTitle) { model.navigation.open(.disc(id: track.discID)) }
                    .buttonStyle(.link)
                    .font(.title3)
            }
            if player.isPreview { TagBadge(text: "试听") }
        }
    }

    private var requestButton: some View {
        Button {
            failure = nil
            if player.isDiscovery { player.next() } else { isRequesting = true }
        } label: {
            HStack(spacing: 8) {
                if isRequesting || (player.isDiscovery && player.isLoading) {
                    ProgressView().controlSize(.small)
                    Text("正在寻找下一首")
                } else {
                    Label(player.isDiscovery ? "换一首" : failure == nil ? "开始随便听听" : "再试一次", systemImage: "shuffle")
                }
            }
            .frame(minWidth: 180)
        }
        .buttonStyle(.borderedProminent)
        .buttonBorderShape(.capsule)
        .controlSize(.extraLarge)
        .disabled(isRequesting)
    }
}
