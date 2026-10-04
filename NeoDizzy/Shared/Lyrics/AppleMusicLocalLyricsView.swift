// Adapted from MeloX AppleMusicLyricsView (GPL-3.0), commit
// 1fe5fbab3f554e8529c4847fc54281a472b7b61a. Uses its default typography,
// focus geometry, distance blur, viewport mask and press interaction.
// The data adapter accepts local line timestamps; no network lyric provider.
import SwiftUI

struct AppleMusicLocalLyricsView: View {
    let lyrics: LocalLyrics
    let playerFrame: CGRect
    @AppStorage("lyrics.focusPosition") private var focusPosition = 0.5
    let activeID: Int?
    let bottomOverlayHeight: CGFloat
    let isActive: Bool
    @Binding var isInterfaceHidden: Bool
    let onSeek: (Double) -> Void
    /// macOS 侧边歌词面板使用较小的固定字号和随系统外观变化的文字颜色；iOS 播放页保持默认值。
    var fixedFontSize: CGFloat? = nil
    var foreground: Color = .white

    @Environment(\.accessibilityReduceMotion) private var reducesMotion
    @Environment(\.colorSchemeContrast) private var contrast
    @ScaledMetric private var scaledFontSize = AppleMusicLyricsTypographyProfile.iOS26_6.primaryFontSize
    @State private var browsing = false
    @State private var interacting = false
    @State private var resumeGeneration = 0
    @State private var rowHeights: [Int: CGFloat] = [:]
    @State private var visibility = LyricsScrollInterfaceVisibilityTracker()
    private let motion = AppleMusicLyricsMotionProfile.iOS26_6
    private var fontSize: CGFloat { fixedFontSize ?? scaledFontSize }

    var body: some View {
        GeometryReader { viewport in
            let height = viewport.size.height
            let referenceHeight = max(height - min(max(bottomOverlayHeight, 0), max(height - 1, 0)), 1)
            let lineHeight = LyricsFontMetrics.boldLineHeight(size: fontSize)
            let focusedHeight = activeID.flatMap { rowHeights[$0] } ?? lineHeight
            let visibleHeight = isInterfaceHidden ? height : referenceHeight
            let preferredY = playerFrame.minY + playerFrame.height * min(max(focusPosition.isFinite ? focusPosition : 0.5, 0.05), 0.8)
                - viewport.frame(in: .global).minY
            let focusTop = min(max(preferredY - focusedHeight / 2, visibleHeight * 0.08),
                               max(visibleHeight * 0.08, visibleHeight * 0.84 - focusedHeight))
            let anchor = min(max(focusTop / max(height - focusedHeight, 1), 0), 1)
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: motion.lineSpacing) {
                        ForEach(lyrics.lines) { line in
                            lyricRow(line, focusTop: focusTop, stride: lineHeight + motion.lineSpacing)
                                .id(line.id)
                        }
                    }
                    .padding(.top, max(focusTop, motion.firstLineStartOffset))
                    .padding(.bottom, max(height * (1 - anchor), 40))
                }
                .coordinateSpace(name: "localLyricsViewport")
                .scrollIndicators(.hidden)
                .scrollClipDisabled()
                .mask(viewportMask(referenceRatio: referenceHeight / max(height, 1)))
                .onScrollPhaseChange { _, phase in
                    interacting = phase == .interacting || phase == .decelerating || phase == .tracking
                    if phase == .interacting {
                        browsing = true
                        resumeGeneration += 1
                        visibility.begin(isInterfaceVisible: !isInterfaceHidden)
                    } else if phase == .idle {
                        visibility.end()
                        resumeGeneration += 1
                    }
                }
                .onScrollGeometryChange(for: CGFloat.self) { $0.contentOffset.y } action: { old, new in
                    guard interacting else { return }
                    if let visible = visibility.update(offsetDelta: new - old, hideThreshold: 120) {
                        isInterfaceHidden = !visible
                    }
                }
                .task(id: resumeGeneration) {
                    guard browsing, !interacting else { return }
                    do {
                        try await Task.sleep(for: .seconds(3))
                        try Task.checkCancellation()
                        browsing = false
                        focus(proxy, anchor: anchor)
                    } catch { }
                }
                .onChange(of: anchor) { _, _ in
                    if !browsing { focus(proxy, anchor: anchor) }
                }
                .onChange(of: activeID) { _, _ in
                    if !browsing { focus(proxy, anchor: anchor) }
                }
                .onChange(of: isActive) { _, active in
                    if active { browsing = false; focus(proxy, anchor: anchor) }
                    else { resumeGeneration += 1 }
                }
                .onChange(of: browsing) { _, value in
                    if !value { focus(proxy, anchor: anchor) }
                }
                .onAppear { focus(proxy, anchor: anchor, animated: false) }
            }
        }
    }

    private func lyricRow(_ line: LyricLine, focusTop: CGFloat, stride: CGFloat) -> some View {
        let focused = line.id == activeID
        let disablesBlur = focused || browsing || contrast == .increased || reducesMotion
        let opacity = focused || browsing ? 1 : contrast == .increased
            ? motion.increasedContrastDeselectedTextOpacity : motion.deselectedTextOpacity
        return LyricPressInteraction(isSelected: false, allowsLongPress: false, onTap: {
            onSeek(line.time)
            browsing = false
            resumeGeneration += 1
            isInterfaceHidden = false
        }, onLongPress: {}) { pressProgress in
            Text(line.text.isEmpty ? "♪" : line.text)
                .font(.system(size: fontSize, weight: .bold))
                .multilineTextAlignment(.leading)
                .foregroundStyle(foreground.opacity(opacity))
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(foreground.opacity(pressProgress * 0.12), in: .rect(cornerRadius: 12))
        }
        .scaleEffect(focused ? 1 : motion.deselectedScale, anchor: .topLeading)
        .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { rowHeights[line.id] = $0 }
        .visualEffect { content, geometry in
            let distance = abs(geometry.frame(in: .named("localLyricsViewport")).midY - focusTop)
            let relativeDistance = max(distance / max(stride, 1), 0)
            let blur = motion.nonFocusedBlurRadius + (motion.maximumNonFocusedBlurRadius - motion.nonFocusedBlurRadius)
                * min(max(relativeDistance - 1, 0), 1)
            return content.blur(radius: disablesBlur ? 0 : blur)
        }
        .animation(reducesMotion ? nil : .timingCurve(
            motion.focusBlurTransitionControlPoint1X, motion.focusBlurTransitionControlPoint1Y,
            motion.focusBlurTransitionControlPoint2X, motion.focusBlurTransitionControlPoint2Y,
            duration: motion.focusBlurTransitionDuration), value: focused)
        .accessibilityAddTraits(focused ? .isSelected : [])
    }

    private func viewportMask(referenceRatio: CGFloat) -> some View {
        let bottomClear = isInterfaceHidden ? 1 : referenceRatio
        let bottomFade = isInterfaceHidden ? 0.08 : 0.16 * referenceRatio
        return LinearGradient(stops: [
            .init(color: .clear, location: 0),
            .init(color: .black, location: 0.08 * referenceRatio),
            .init(color: .black, location: max(0.08 * referenceRatio, bottomClear - bottomFade)),
            .init(color: .clear, location: bottomClear),
            .init(color: .clear, location: 1)
        ], startPoint: .top, endPoint: .bottom)
        .animation(reducesMotion ? nil : .smooth(duration: 0.35), value: isInterfaceHidden)
    }

    private func focus(_ proxy: ScrollViewProxy, anchor: CGFloat, animated: Bool = true) {
        guard isActive, let id = activeID else { return }
        let spring = motion.lineChangeSpring
        withAnimation(animated && !reducesMotion ? .interpolatingSpring(
            mass: spring.mass, stiffness: spring.stiffness, damping: spring.damping) : nil) {
            proxy.scrollTo(id, anchor: UnitPoint(x: 0.5, y: anchor))
        }
    }
}
