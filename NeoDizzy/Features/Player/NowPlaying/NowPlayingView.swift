// Direct source port from MeloX (GPL-3.0), b8bc60f.
// Data/settings adapters retain NeoDizzy playback and lyric sources.
import SwiftUI
import UniformTypeIdentifiers

struct NowPlayingView: View {
    static let transitionID = "nowPlaying"
    private static let portraitHorizontalPadding: CGFloat = 32
    @Environment(\.dismiss) private var dismiss
    @Environment(\.accessibilityReduceMotion) private var accessibilityReduceMotion
    @Environment(\.accessibilityVoiceOverEnabled) private var accessibilityVoiceOverEnabled
    @Environment(PlayerStore.self) private var player
    @Environment(OfflineLibraryStore.self) private var library
    @State private var pageTransition: NowPlayingTransitionCoordinator
    @State private var showsLyricsControls = true
    @State private var appleMusicControlsActivityGeneration = 0
    @State private var isQueueSongHeaderHidden = false
    @State private var queueSongHeaderOffset: CGFloat = 0
    @State private var artworkPageFrame = CGRect.zero
    @State private var preparedLyricsSongID: Track.ID?
    @State private var playerFrame = CGRect.zero
    @State private var lyricsModel = NowPlayingLyricsModel()
    @State private var importingLyrics = false
    @State private var importTrackID: String?
    @Namespace private var pageArtworkNamespace
    private var page: NowPlayingPage { pageTransition.page }
    init(initialPage: NowPlayingPage = .artwork) {
        _pageTransition = State(initialValue: NowPlayingTransitionCoordinator(initialPage: initialPage))
    }
    var body: some View {
        GeometryReader { proxy in
            ZStack {
                NowPlayingBackground(
                    artworkURL: player.currentTrack?.coverURL,
                    isBehindLyrics: page == .lyrics
                )
                if let song = player.currentTrack {
                    if proxy.size.width > proxy.size.height {
                        NowPlayingLandscapeView(
                            page: pageSelection, pageTransition: pageTransition,
                            showsLyricsControls: showsLyricsControls, song: song,
                            lyrics: lyricsModel.lyrics, lyricError: lyricsModel.error,
                            playerFrame: playerFrame, artworkNamespace: pageArtworkNamespace,
                            onDismiss: { dismiss() }, onInterfaceInteraction: handleLyricsInterfaceInteraction,
                            onInterfaceVisibilityChange: setAppleMusicLyricsControlsVisible,
                            onLyricsContentPrepared: { markLyricsContentPrepared(for: song.id) }
                        )
                    } else { portraitContent(for: song) }
                } else {
                    ContentUnavailableView("当前没有播放歌曲", systemImage: "music.note").foregroundStyle(.white)
                }
            }
        }
        .foregroundStyle(.white)
        .environment(\.colorScheme, .dark)
        .onGeometryChange(for: CGRect.self) { $0.frame(in: .global) } action: { playerFrame = $0 }
        .task(id: "\(player.currentTrack?.id ?? "")/\(library.contentRevision)/\(lyricsModel.revision)") {
            guard let track = player.currentTrack else { return }
            preparedLyricsSongID = nil
            await lyricsModel.load(track: track, library: library, player: player)
        }
        .task(id: transitionSettlementTaskID) { await settlePageTransition() }
        .task(id: lyricsEntranceTaskID) { await presentLyricsEntrance() }
        .onChange(of: page) { _, _ in showsLyricsControls = true }
        .onChange(of: player.currentTrack == nil) { _, empty in if empty { dismiss() } }
        .fileImporter(isPresented: $importingLyrics, allowedContentTypes: [.data, .plainText]) { result in
            guard let id = importTrackID, case .success(let url) = result else { return }
            Task { await lyricsModel.importFile(url, trackID: id) }
        }
    }

    private func portraitContent(for song: Track) -> some View {
        VStack(spacing: 0) {
            dismissalHandle

            pageContent(for: song)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .overlay(alignment: .bottom) {
                    portraitPlayerControlsLayer(for: song)
                }
        }
        .padding(.horizontal, Self.portraitHorizontalPadding)
        .safeAreaPadding(.bottom, 3)
    }

    private func portraitPlayerControlsLayer(
        for song: Track
    ) -> some View {
        ZStack(alignment: .bottom) {
            portraitPlayerControls(for: song)
                .allowsHitTesting(!hidesLyricsControls)
                .accessibilityHidden(hidesLyricsControls)


        }
        .frame(height: NowPlayingBottomControls.overlayHeight)
    }

    private func portraitPlayerControls(for song: Track) -> some View {
        NowPlayingBottomControls(
            song: song,
            page: pageSelection,
            showsLyricsUtilities:
                usesExpandedAppleMusicLyricsLayout,
            hasLyricsTranslations: hasLyricsTranslations,
            hasLyricsRomanizations: hasLyricsRomanizations,
            isInterfaceHidden: hidesLyricsControls
        )
    }

    private var pageSelection: Binding<NowPlayingPage> {
        Binding(
            get: { page },
            set: { newPage in
                pageTransition.select(
                    newPage,
                    usesAppleMusicLyrics:
                        true,
                    isQueueSongHeaderHidden:
                        isQueueSongHeaderHidden,
                    motion: NowPlayingPageTransition.motion
                )
            }
        )
    }

    private var hidesLyricsControls: Bool {
        page == .lyrics && !showsLyricsControls
    }

    private var usesAutoHidingAppleMusicInterface: Bool {
        page == .lyrics
    }

    private var hasLyricsTranslations: Bool { false }
    private var hasLyricsRomanizations: Bool { false }

    private var usesExpandedAppleMusicLyricsLayout: Bool {
        page == .lyrics
    }

    private var dismissalHandle: some View {
        ZStack(alignment: .top) {
            Capsule()
                .fill(.white.opacity(0.52))
                .frame(width: 60, height: 5)
                .padding(.top, 8)
        }
        .frame(maxWidth: .infinity)
        .frame(height: 34)
        .contentShape(.rect)
        .onTapGesture {
            dismiss()
        }
        .accessibilityElement()
        .accessibilityLabel("收起播放器")
        .accessibilityHint("返回上一页")
        .accessibilityAction {
            dismiss()
        }
    }

    private func pageContent(for song: Track) -> some View {
        ZStack(alignment: .top) {
            transientArtworkPageContent(for: song)
                .frame(
                    maxWidth: .infinity,
                    maxHeight: .infinity
                )
                .clipped()

            residentQueuePage(for: song)

            residentAppleMusicLyricsPage(for: song)

            if page != .artwork {
                sharedPortraitSongHeader(for: song)
                    .offset(y: sharedPortraitSongHeaderOffset)
                    .clipped()
                    .transition(
                        NowPlayingPageTransition.songHeader(
                            reducesMotion: accessibilityReduceMotion
                        )
                    )
            }

        }
        .background {
            if keepsStableArtworkFrameMeasurement {
                artworkFrameMeasurement(for: song)
            }
        }
        .overlay {
            GeometryReader { _ in
                if portraitArtworkFrame.width > 0 {
                    NowPlayingPortraitArtwork(
                        song: song,
                        isArtworkPage: page == .artwork
                    )
                    .frame(
                        width: portraitArtworkFrame.width,
                        height: portraitArtworkFrame.height
                    )
                    .position(
                        x:
                            portraitArtworkFrame.midX
                            + Self.portraitHorizontalPadding,
                        y: portraitArtworkFrame.midY
                    )
                    .animation(
                        accessibilityReduceMotion
                            ? nil
                            : NowPlayingPageTransition
                                .motion
                                .artworkResize
                                .animation,
                        value: isPortraitArtworkExpanded
                    )
                    .allowsHitTesting(false)
                }
            }
            // Keep page-transition clipping vertically while allowing the
            // expanded artwork to use the portrait layout's side margins.
            .clipped()
            .padding(
                .horizontal,
                -Self.portraitHorizontalPadding
            )
        }
        .coordinateSpace(
            name: NowPlayingPortraitCoordinateSpace.name
        )
    }

    @ViewBuilder
    private func transientArtworkPageContent(
        for song: Track
    ) -> some View {
        if page == .artwork {
            NowPlayingArtworkPage(
                song: song,
                artworkNamespace: pageArtworkNamespace,
                usesArtworkTransition: false,
                showsArtwork: false,
                onArtworkFrameChange:
                    recordPresentedArtworkPageFrame
            )
            .transition(
                pageContentTransition(for: .artwork)
            )
        }
    }

    private func artworkFrameMeasurement(
        for song: Track
    ) -> some View {
        NowPlayingArtworkPage(
            song: song,
            artworkNamespace: pageArtworkNamespace,
            usesArtworkTransition: false,
            showsArtwork: false,
            onArtworkFrameChange: recordArtworkPageFrame
        )
        .hidden()
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }

    private var keepsStableArtworkFrameMeasurement: Bool {
        page != .artwork || pageTransition.transition != nil
    }

    private func recordPresentedArtworkPageFrame(
        _ frame: CGRect
    ) {
        // The artwork page enters from below. Its geometry includes that
        // temporary transition offset, so keep using the resident
        // measurement until the page transition has settled.
        guard pageTransition.transition == nil else { return }
        recordArtworkPageFrame(frame)
    }

    private func recordArtworkPageFrame(_ frame: CGRect) {
        guard frame.width.isFinite,
              frame.height.isFinite,
              frame.minX.isFinite,
              frame.minY.isFinite,
              frame.width > 0,
              frame.height > 0 else {
            return
        }
        let tolerance: CGFloat = 0.5
        guard abs(artworkPageFrame.minX - frame.minX) > tolerance
                || abs(artworkPageFrame.minY - frame.minY) > tolerance
                || abs(artworkPageFrame.width - frame.width) > tolerance
                || abs(artworkPageFrame.height - frame.height) > tolerance else {
            return
        }
        artworkPageFrame = frame
    }

    private func residentQueuePage(
        for song: Track
    ) -> some View {
        let visualState = residentQueueVisualState

        return NowPlayingQueuePage(
            song: song,
            presentation: .portrait,
            artworkNamespace: pageArtworkNamespace,
            usesArtworkTransition: false,
            showsSongHeader: false,
            onSongHeaderHiddenChange: {
                isQueueSongHeaderHidden = $0
            },
            onSongHeaderOffsetChange: {
                queueSongHeaderOffset = $0
            }
        )
        .clipped()
        .nowPlayingQueuePagePresentation(
            visualState: visualState,
            opacityTransition: pageTransition.queueOpacityTransition,
            spatialTransition: pageTransition.queueSpatialTransition,
            opacitySpec:
                pageTransition.queueOpacityTransition.targetProgress >= 1
                    ? NowPlayingPageTransition.motion
                        .queueOpacityPresentation
                    : NowPlayingPageTransition.motion
                        .queueOpacityDismissal,
            presentationScale:
                NowPlayingPageTransition.motion.queuePresentationScale,
            reducesMotion: accessibilityReduceMotion
        )
        .allowsHitTesting(page == .queue)
        .accessibilityHidden(page != .queue)
    }

    private func portraitLyricsPage(
        for song: Track,
        onInitialFocusPrepared: (() -> Void)? = nil
    ) -> some View {
        NowPlayingLyricsPage(
            song: song, lyrics: lyricsModel.lyrics, errorMessage: lyricsModel.error,
            isActive: page == .lyrics, isInterfaceHidden: hidesLyricsControls,
            artworkNamespace: pageArtworkNamespace, showsSongHeader: false,
            playerFrame: playerFrame,
            onInterfaceVisibilityChange: setAppleMusicLyricsControlsVisible,
            onInitialFocusPrepared: onInitialFocusPrepared
        )
        .accessibilityAction(named: lyricsInterfaceAccessibilityActionName) {
            handleLyricsInterfaceInteraction()
        }
    }

    private func residentAppleMusicLyricsPage(
        for song: Track
    ) -> some View {
        let visualState = residentLyricsVisualState

        return portraitLyricsPage(
            for: song,
            onInitialFocusPrepared: {
                markLyricsContentPrepared(for: song.id)
            }
        )
        .id(song.id)
        .nowPlayingLyricsPagePresentation(
            visualState: visualState,
            opacityTransition:
                pageTransition.lyricsOpacityTransition,
            spatialTransition:
                pageTransition.lyricsSpatialTransition,
            opacitySpec:
                pageTransition.lyricsOpacityTransition
                    .targetProgress >= 1
                    ? NowPlayingPageTransition.motion
                        .lyricsOpacityPresentation
                    : NowPlayingPageTransition.motion
                        .lyricsOpacityDismissal,
            presentationScale:
                NowPlayingPageTransition.motion
                    .lyricsPresentationScale,
            reducesMotion: accessibilityReduceMotion
        )
        .allowsHitTesting(page == .lyrics)
        .accessibilityHidden(page != .lyrics)
    }

    private var residentLyricsVisualState: NowPlayingPageVisualState {
        NowPlayingPageTransition.motion.residentLyricsState(
            selectedPage: page,
            transition: pageTransition.transition,
            isEntrancePresented:
                pageTransition.isLyricsEntrancePresented
        )
    }

    private var residentQueueVisualState: NowPlayingPageVisualState {
        NowPlayingPageTransition.motion.residentQueueState(
            selectedPage: page,
            transition: pageTransition.transition
        )
    }

    private func sharedPortraitSongHeader(
        for song: Track
    ) -> some View {
        NowPlayingSongHeader(
            song: song,
            artworkNamespace: pageArtworkNamespace,
            usesReferenceLayout: true,
            usesArtworkTransition: false,
            showsArtwork: false,
            onImportLyrics: {
                importTrackID = song.id
                importingLyrics = true
            }
        )
    }

    private var portraitArtworkFrame: CGRect {
        if page == .artwork {
            return displayedArtworkPageFrame
        }

        return CGRect(
            x: 0,
            y: sharedPortraitSongHeaderOffset,
            width: NowPlayingSongHeader.referenceHeight,
            height: NowPlayingSongHeader.referenceHeight
        )
    }

    private var displayedArtworkPageFrame: CGRect {
        guard !isPortraitArtworkExpanded else {
            return artworkPageFrame
        }
        let horizontalInset =
            artworkPageFrame.width
            * (1 - NowPlayingArtworkPage.pausedArtworkScale)
            / 2
        let verticalInset =
            artworkPageFrame.height
            * (1 - NowPlayingArtworkPage.pausedArtworkScale)
            / 2
        return artworkPageFrame.insetBy(
            dx: horizontalInset,
            dy: verticalInset
        )
    }

    private var isPortraitArtworkExpanded: Bool {
        player.isPlaying
    }

    private var sharedPortraitSongHeaderOffset: CGFloat {
        page == .queue ? queueSongHeaderOffset : 0
    }

    private func pageContentTransition(
        for destination: NowPlayingPage
    ) -> AnyTransition {
        if NowPlayingPageTransition.isDirectLyricsQueueTransition(
            from: pageTransition.sourcePage,
            to: pageTransition.destinationPage
        ) {
            return NowPlayingPageTransition.directAlternateContent(
                reducesMotion: accessibilityReduceMotion
            )
        }

        return NowPlayingPageTransition.content(
            for: destination,
            entersFromHiddenQueue:
                pageTransition.entersFromHiddenQueue,
            reducesMotion: accessibilityReduceMotion
        )
    }

    private var transitionSettlementTaskID:
        NowPlayingTransitionSettlementTaskID {
        NowPlayingTransitionSettlementTaskID(
            requestID: pageTransition.transition?.id,
            isLyricsEntrancePresented:
                pageTransition.isLyricsEntrancePresented
        )
    }

    private var lyricsEntranceTaskID:
        NowPlayingLyricsEntranceTaskID {
        NowPlayingLyricsEntranceTaskID(
            requestID: pageTransition.pendingLyricsEntrance?
                .requestID,
            songID: player.currentTrack?.id,
            preparedSongID: preparedLyricsSongID,
            isContentPrepared: isLyricsContentPrepared
        )
    }

    private func settlePageTransition() async {
        guard let transition = pageTransition.transition,
              pageTransition.isLyricsEntrancePresented else {
            return
        }

        let now = ContinuousClock.now
        let settlementDuration = accessibilityReduceMotion
            ? 0
            : max(
                NowPlayingPageTransition.motion.settlementDuration(
                    for: transition
                ),
                pageTransition.activeMotionRemainingDuration(at: now)
            )
        if settlementDuration > 0 {
            do {
                try await Task.sleep(
                    for: .seconds(settlementDuration)
                )
            } catch {
                return
            }
        }
        guard !Task.isCancelled,
              page == transition.destination,
              pageTransition.transition?.id == transition.id else {
            return
        }

        var transaction = Transaction(animation: nil)
        transaction.disablesAnimations = true
        withTransaction(transaction) {
            pageTransition.settleTransition(
                requestID: transition.id
            )
        }
    }

    private func presentLyricsEntrance() async {
        guard let pendingEntrance =
            pageTransition.pendingLyricsEntrance else {
            return
        }
        let requestID = pendingEntrance.requestID

        await Task.yield()
        guard !Task.isCancelled,
              pageTransition.pendingLyricsEntrance?.requestID
                == requestID else {
            return
        }

        if accessibilityReduceMotion {
            var transaction = Transaction(animation: nil)
            transaction.disablesAnimations = true
            withTransaction(transaction) {
                pageTransition.presentLyricsEntrance(
                    requestID: requestID,
                    motion: NowPlayingPageTransition.motion
                )
            }
            return
        }

        guard page == .lyrics,
              pageTransition.usesStagedLyricsEntrance else {
            return
        }

        let presentationDeadline = isLyricsContentPrepared
            ? pendingEntrance.notBefore
            : pendingEntrance.fallbackAt
        let remainingDelay = ContinuousClock.now.duration(
            to: presentationDeadline
        )
        if remainingDelay > .zero {
            do {
                try await Task.sleep(for: remainingDelay)
            } catch {
                return
            }
        }

        guard !Task.isCancelled,
              page == .lyrics,
              pageTransition.pendingLyricsEntrance?.requestID
                == requestID else {
            return
        }

        pageTransition.presentLyricsEntrance(
            requestID: requestID,
            motion: NowPlayingPageTransition.motion
        )
    }

    private var isLyricsContentPrepared: Bool {
        (lyricsModel.lyrics?.isEmpty == true || lyricsModel.error != nil)
            || preparedLyricsSongID == player.currentTrack?.id
    }

    private func markLyricsContentPrepared(for songID: Track.ID) {
        guard player.currentTrack?.id == songID else { return }
        preparedLyricsSongID = songID
    }

    private var lyricsInterfaceAccessibilityActionName: String { "显示播放控件" }

    private func handleLyricsInterfaceInteraction() {
        registerAppleMusicControlsActivity()
    }

    private func registerAppleMusicControlsActivity() {
        guard usesAutoHidingAppleMusicInterface else { return }

        appleMusicControlsActivityGeneration &+= 1
        guard !showsLyricsControls else { return }

        withAnimation(
            NowPlayingInterfaceTransition.interfaceAnimation(
                isVisible: true,
                reducesMotion: accessibilityReduceMotion
            )
        ) {
            showsLyricsControls = true
        }
    }

    private func setAppleMusicLyricsControlsVisible(_ isVisible: Bool) {
        guard usesAutoHidingAppleMusicInterface else { return }
        if isVisible {
            registerAppleMusicControlsActivity()
            return
        }

        guard showsLyricsControls,
              !accessibilityVoiceOverEnabled else {
            return
        }
        cancelAppleMusicControlsAutoHide()
        withAnimation(
            NowPlayingInterfaceTransition.interfaceAnimation(
                isVisible: false,
                reducesMotion: accessibilityReduceMotion
            )
        ) {
            showsLyricsControls = false
        }
    }



    private func cancelAppleMusicControlsAutoHide() {
        appleMusicControlsActivityGeneration &+= 1
    }

}

private struct NowPlayingTransitionSettlementTaskID: Equatable {
    let requestID: UUID?
    let isLyricsEntrancePresented: Bool
}

private struct NowPlayingLyricsEntranceTaskID: Equatable {
    let requestID: UUID?
    let songID: Track.ID?
    let preparedSongID: Track.ID?
    let isContentPrepared: Bool
}
