// Layout adapted from MeloX (GPLv3), StandardMusicCollectionDetailHero.
import Nuke
import NukeUI
import SwiftUI

struct AlbumHero<Subtitle: View, Actions: View>: View {
    let artworkURL: URL?
    let title: String
    let metadata: String
    @ViewBuilder let subtitle: () -> Subtitle
    @ViewBuilder let actions: () -> Actions

    var body: some View {
        VStack(spacing: 0) {
            ArtworkImage(url: artworkURL, cornerRadius: 12)
                .containerRelativeFrame(.horizontal) { width, _ in min(width * 0.68, 300) }
                .shadow(color: .black.opacity(0.18), radius: 18, y: 10)
            Text(title)
                .font(.title2.bold()).multilineTextAlignment(.center).lineLimit(2)
                .padding(.top, 24).padding(.horizontal, 24)
            subtitle().font(.title3).lineLimit(1).padding(.top, 8)
            Text(metadata).font(.subheadline.weight(.medium)).foregroundStyle(.secondary)
                .multilineTextAlignment(.center).padding(.top, 7)
            actions().padding(.top, 17)
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 70).padding(.bottom, 22)
    }
}

struct AlbumPlaybackActions: View {
    let isEmpty: Bool
    var isPreview = false
    var webURL: URL?
    var batchEdit: (() -> Void)?
    let play: (Bool) -> Void
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        GlassEffectContainer(spacing: 14) {
            HStack(spacing: 14) {
                Button { play(true) } label: {
                    Image(systemName: "shuffle").font(.title2.weight(.semibold)).frame(width: 30, height: 30)
                }
                .buttonStyle(.glass).buttonBorderShape(.circle)
                .accessibilityLabel(isPreview ? "随机试听" : "随机播放")
                .disabled(isEmpty)
                Button { play(false) } label: {
                    Label(isPreview ? "试听" : "播放", systemImage: "play.fill")
                        .font(.title3.bold()).frame(minWidth: 116)
                }
                .buttonStyle(.glassProminent).buttonBorderShape(.capsule)
                .tint(colorScheme == .dark ? .white : .black)
                .foregroundStyle(colorScheme == .dark ? .black : .white)
                .disabled(isEmpty)
                if let batchEdit {
                    Button(action: batchEdit) {
                        Image(systemName: "square.and.pencil")
                            .resizable()
                            .scaledToFit()
                            .fontWeight(.semibold)
                            .frame(width: 24, height: 24)
                            // The square carries most of the visual weight; compensate
                            // for the pencil extending the symbol's upper-right bounds.
                            .offset(x: 1, y: -1)
                            .frame(width: 30, height: 30, alignment: .center)
                    }
                    .buttonStyle(.glass).buttonBorderShape(.circle)
                    .accessibilityLabel("批量编辑")
                }
                if let webURL {
                    Link(destination: webURL) {
                        Image(systemName: "safari").font(.title2.weight(.semibold)).frame(width: 30, height: 30)
                    }
                    .buttonStyle(.glass).buttonBorderShape(.circle).accessibilityLabel("在网页中打开")
                }
            }
            .controlSize(.large)
        }
    }
}

/// Nuke owns cancellation and caches the downsampled request; URL identity prevents stale artwork reuse.
struct AlbumArtworkBackground: View {
    let url: URL?
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        GeometryReader { proxy in
            ZStack {
                colorScheme == .dark ? Color(white: 0.1) : Color(white: 0.96)
                LazyImage(request: request) { state in
                    if let image = state.image {
                        image.resizable().scaledToFill()
                            .frame(width: proxy.size.width, height: proxy.size.height)
                            .blur(radius: 60).opacity(0.22)
                    }
                }
                .id(url)
                LinearGradient(colors: colorScheme == .dark
                    ? [.black.opacity(0.08), .black.opacity(0.24), .black.opacity(0.4)]
                    : [.white.opacity(0.06), .white.opacity(0.16), .white.opacity(0.3)],
                    startPoint: .top, endPoint: .bottom)
            }
            .frame(width: proxy.size.width, height: proxy.size.height).clipped()
        }
        .ignoresSafeArea().accessibilityHidden(true)
    }

    private var request: ImageRequest? {
        guard let url else { return nil }
        var request = ImageRequest(url: url)
        request.thumbnail = .init(size: CGSize(width: 160, height: 160), contentMode: .aspectFill)
        return request
    }
}

// Adapted from upstream MeloX Features/Playlist/PlaylistTrackList.swift (GPL-3.0).
// Album rows use this layout rather than MeloX's general-purpose TrackRowView.
struct AlbumTrackRow: View {
    let track: Track
    var isPreview = false
    var editTags: (() -> Void)?
    let play: () -> Void
    @Environment(PlayerStore.self) private var player

    private var isCurrent: Bool { player.currentTrack?.id == track.id }

    var body: some View {
        HStack(spacing: 4) {
            playbackButton
            if isPreview {
                Text("试听").font(.caption2).foregroundStyle(.secondary)
            }
            Menu {
                Button(action: primaryAction) {
                    Label(isCurrent && player.isPlaying ? "暂停" : "播放", systemImage: isCurrent && player.isPlaying ? "pause.fill" : "play.fill")
                }
                if let editTags {
                    Button("编辑音乐标签", systemImage: "pencil", action: editTags)
                }
            } label: {
                Image(systemName: "ellipsis")
                    .font(.body.weight(.semibold))
                    .frame(width: 42, height: 44)
                    .contentShape(.rect)
            }
            .accessibilityLabel("\(track.title)的更多操作")
        }
        .padding(.leading, 20)
        .padding(.trailing, 8)
        .padding(.vertical, 11)
        .foregroundStyle(.primary)
        .tint(.primary)
        .background(isCurrent ? Color.primary.opacity(0.10) : .clear)
        .accessibilityElement(children: .contain)
    }

    @ViewBuilder private var playbackButton: some View {
        if let editTags {
            button.highPriorityGesture(LongPressGesture(minimumDuration: 0.5).onEnded { _ in editTags() })
                .accessibilityAction(named: "编辑音乐标签", editTags)
        } else {
            button
        }
    }

    private var button: some View {
        Button(action: primaryAction) {
            HStack(spacing: 12) {
                leadingContent
                Text(track.title)
                    .font(.body)
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(track.title)，\(track.artists)")
        .accessibilityValue(isCurrent ? "当前播放" : "")
    }

    @ViewBuilder private var leadingContent: some View {
        if isCurrent {
            ZStack {
                Circle().stroke(Color.primary.opacity(0.60), lineWidth: 1.5)
                if player.isLoading {
                    ProgressView().controlSize(.mini)
                } else {
                    Image(systemName: player.isPlaying ? "pause.fill" : "play.fill")
                        .font(.caption.weight(.bold))
                }
            }
            .frame(width: 32, height: 32)
            .frame(width: 40)
        } else {
            Text(track.number)
                .font(.title3)
                .foregroundStyle(.secondary)
                .monospacedDigit()
                .lineLimit(1)
                .minimumScaleFactor(0.8)
                .frame(width: 40, alignment: .center)
        }
    }

    private func primaryAction() {
        if isCurrent { player.togglePlayback() } else { play() }
    }
}

