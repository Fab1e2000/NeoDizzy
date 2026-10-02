// Layout adapted from MeloX (GPLv3), StandardMusicCollectionDetailHero.
import Nuke
import CoreImage.CIFilterBuiltins
import SwiftUI

struct AlbumHero<Subtitle: View, Actions: View>: View {
    let artworkURL: URL?
    let title: String
    let metadata: String
    @ViewBuilder let subtitle: () -> Subtitle
    @ViewBuilder let actions: () -> Actions

    var body: some View {
        VStack(spacing: 0) {
            ArtworkImage(url: artworkURL, cornerRadius: 12, decodeSize: AlbumArtworkPreload.heroSize)
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
        .padding(.top, 24).padding(.bottom, 22)
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

// Adapted from MeloX v1.2.1 AlbumDetailContent / MusicCollectionArtworkBackdrop
// and ArtworkAccentColorProvider (GPL-3.0).
struct AlbumDetailScrollView<Content: View>: View {
    let artworkURL: URL?
    @ViewBuilder var content: Content

    var body: some View {
        ZStack {
            AlbumArtworkBackground(url: artworkURL)
                .id(artworkURL)
            ScrollView { content }
                .scrollIndicators(.hidden)
        }
    }
}

struct AlbumArtworkBackground: View {
    let url: URL?
    @State private var backdrop: CGImage?

    init(url: URL?) {
        self.url = url
        // URL identity is owned by AlbumDetailScrollView; seed the first frame from cache.
        _backdrop = State(initialValue: url.flatMap { AlbumBackdropCache.shared.image(for: $0) })
    }

    var body: some View {
        GeometryReader { proxy in
            ZStack {
                DizzyPalette.background
                if let backdrop {
                    Image(decorative: backdrop, scale: 1)
                        .resizable()
                        .scaledToFill()
                        .frame(width: proxy.size.width, height: proxy.size.height)
                        .opacity(0.22)
                }
                LinearGradient(
                    colors: [.black.opacity(0.08), .black.opacity(0.24), .black.opacity(0.40)],
                    startPoint: .top, endPoint: .bottom
                )
            }
            .frame(width: proxy.size.width, height: proxy.size.height)
            .clipped()
        }
        .ignoresSafeArea()
        .accessibilityHidden(true)
        .task(id: url) {
            guard backdrop == nil, let url else { return }
            let image = await AlbumBackdropProvider.shared.image(for: url)
            guard !Task.isCancelled else { return }
            backdrop = image
        }
    }
}

/// Cache preblurred images; extend edge pixels before blurring, as upstream does.
private actor AlbumBackdropProvider {
    static let shared = AlbumBackdropProvider()
    private let context = CIContext()

    func image(for url: URL) async -> CGImage? {
        if let cached = AlbumBackdropCache.shared.image(for: url) { return cached }
        var request = ImageRequest(url: url)
        request.thumbnail = .init(size: CGSize(width: 160, height: 160), unit: .pixels, contentMode: .aspectFill)
        guard let loaded = try? await ImagePipeline.shared.image(for: request),
              let source = CIImage(image: loaded), !Task.isCancelled else { return nil }
        if let cached = AlbumBackdropCache.shared.image(for: url) { return cached }
        let extent = source.extent.integral
        guard !extent.isEmpty, !extent.isInfinite else { return nil }
        let filter = CIFilter.gaussianBlur()
        filter.inputImage = source.clampedToExtent()
        filter.radius = 18
        guard let output = filter.outputImage?.cropped(to: extent),
              let image = context.createCGImage(output, from: extent) else { return nil }
        AlbumBackdropCache.shared.insert(image, for: url)
        return image
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


// NSCache is thread-safe; immutable CGImages can be read synchronously by the view
// while the background actor inserts completed results.
private nonisolated final class AlbumBackdropCache: @unchecked Sendable {
    static let shared = AlbumBackdropCache()
    private let cache = NSCache<NSURL, CGImage>()
    private init() { cache.totalCostLimit = 8 * 1024 * 1024 }
    func image(for url: URL) -> CGImage? { cache.object(forKey: url as NSURL) }
    func insert(_ image: CGImage, for url: URL) {
        cache.setObject(image, forKey: url as NSURL, cost: image.bytesPerRow * image.height)
    }
}

enum AlbumArtworkPreload {
    // Match the detail hero request so Nuke reuses the decoded image, not just file data.
    static let heroSize = CGSize(width: 300, height: 300)
}

extension View {
    func prefetchAlbumArtwork(url: URL?) -> some View {
        task(id: url) {
            guard let url else { return }
            async let backdrop = AlbumBackdropProvider.shared.image(for: url)
            var request = ImageRequest(url: url)
            request.thumbnail = .init(size: AlbumArtworkPreload.heroSize, contentMode: .aspectFill)
            request.priority = .low
            _ = try? await ImagePipeline.shared.image(for: request)
            _ = await backdrop
        }
    }
}
