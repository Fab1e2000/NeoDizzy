//
//  NeuPlayerView.swift
//  新拟物风格播放器（对应画布上的「示例：播放器」画板）
//
//  要求：iOS 16+（内阴影用到 ShapeStyle.shadow(.inner)）
//

import SwiftUI
import Combine

// MARK: - 配色（浅色 / 深色自动切换）

extension Color {
    /// 背景与控件共用的底色
    static let neuBase      = Color(light: 0xE4E9F0, dark: 0x2A2F37)
    /// 右下方的暗阴影
    static let neuDark      = Color(light: 0xBFC8D4, dark: 0x1B1F25)
    /// 左上方的亮阴影
    static let neuLight     = Color(light: 0xFFFFFF, dark: 0x39404B)
    static let neuText      = Color(light: 0x2B3445, dark: 0xE3E7EE)
    static let neuSecondary = Color(light: 0x56627A, dark: 0xA3ADBD)
    static let neuAccent    = Color(light: 0x3557B8, dark: 0x8FA9F0)
    static let neuLike      = Color(light: 0xB8405E, dark: 0xF08AA3)

    init(light: UInt32, dark: UInt32) {
        self.init(uiColor: UIColor { traits in
            UIColor(hex: traits.userInterfaceStyle == .dark ? dark : light)
        })
    }
}

private extension UIColor {
    convenience init(hex: UInt32) {
        self.init(red: CGFloat((hex >> 16) & 0xFF) / 255,
                  green: CGFloat((hex >> 8) & 0xFF) / 255,
                  blue: CGFloat(hex & 0xFF) / 255,
                  alpha: 1)
    }
}

// MARK: - 新拟物表面：凸起 / 凹陷

/// 与背景同色的形状，靠一亮一暗两道阴影表现凸起或凹陷。
/// `depth` 对应 CSS 里的偏移量；SwiftUI 的 radius ≈ CSS 模糊值的一半，所以两者取同一个数。
struct NeuSurface<S: Shape>: View {
    var shape: S
    var pressed: Bool = false
    var depth: CGFloat = 6

    @Environment(\.colorSchemeContrast) private var contrast

    var body: some View {
        Group {
            if pressed {
                shape.fill(
                    Color.neuBase
                        .shadow(.inner(color: .neuDark, radius: depth, x: depth, y: depth))
                        .shadow(.inner(color: .neuLight, radius: depth, x: -depth, y: -depth))
                )
            } else {
                shape
                    .fill(Color.neuBase)
                    .shadow(color: .neuDark, radius: depth, x: depth, y: depth)
                    .shadow(color: .neuLight, radius: depth, x: -depth, y: -depth)
            }
        }
        // 开启「增强对比度」时补一圈描边，弥补新拟物对比度低的问题
        .overlay {
            if contrast == .increased {
                shape.stroke(Color.neuSecondary, lineWidth: 1)
            }
        }
    }
}

/// 按住时、或处于开启状态（isOn）时显示为凹陷。
struct NeuButtonStyle<S: Shape>: ButtonStyle {
    var shape: S
    var isOn: Bool = false
    var depth: CGFloat = 6

    func makeBody(configuration: Configuration) -> some View {
        let down = isOn || configuration.isPressed
        configuration.label
            .background(NeuSurface(shape: shape, pressed: down, depth: down ? depth * 0.85 : depth))
            .contentShape(shape)
            .animation(.easeOut(duration: 0.12), value: down)
    }
}

// MARK: - 播放器

struct NeuPlayerView: View {
    @State private var isPlaying = false
    @State private var shuffle = false
    @State private var repeatOn = true
    @State private var liked = false
    @State private var progress: Double = 0.38

    /// 示例时长（秒）
    private let duration: Double = 225
    private let ticker = Timer.publish(every: 1, on: .main, in: .common).autoconnect()

    var body: some View {
        ZStack {
            Color.neuBase.ignoresSafeArea()   // 背景必须与控件同色

            VStack(spacing: 34) {
                header
                artwork
                titles
                progressBar
                transport
                Spacer(minLength: 0)
                modeToggles
            }
            .padding(.horizontal, 28)
            .padding(.top, 12)
            .padding(.bottom, 24)
        }
        .foregroundStyle(Color.neuText)
        .onReceive(ticker) { _ in advance() }
    }

    // 顶栏：返回 · 标题 · 收藏
    private var header: some View {
        HStack {
            Button {} label: {
                Image(systemName: "chevron.left")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(Color.neuSecondary)
                    .frame(width: 50, height: 50)
            }
            .buttonStyle(NeuButtonStyle(shape: Circle()))
            .accessibilityLabel("返回")

            Spacer()

            Text("正在播放")
                .font(.subheadline.weight(.semibold))
                .tracking(1.4)
                .foregroundStyle(Color.neuSecondary)

            Spacer()

            Button { liked.toggle() } label: {
                Image(systemName: liked ? "heart.fill" : "heart")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(liked ? Color.neuLike : Color.neuSecondary)
                    .frame(width: 50, height: 50)
            }
            .buttonStyle(NeuButtonStyle(shape: Circle(), isOn: liked, depth: 6))
            .accessibilityLabel("收藏")
            .accessibilityAddTraits(liked ? .isSelected : [])
        }
    }

    // 封面：外圈凸起，内圈凹陷
    private var artwork: some View {
        ZStack {
            NeuSurface(shape: Circle(), depth: 16)
                .frame(width: 270, height: 270)
            NeuSurface(shape: Circle(), pressed: true, depth: 10)
                .frame(width: 210, height: 210)
            Image(systemName: "music.note")
                .font(.system(size: 56, weight: .light))
                .foregroundStyle(Color.neuSecondary.opacity(0.6))
        }
        .accessibilityHidden(true)
    }

    private var titles: some View {
        VStack(spacing: 6) {
            Text("[歌曲名]").font(.title2.weight(.bold))
            Text("[歌手]").font(.subheadline).foregroundStyle(Color.neuSecondary)
        }
    }

    // 进度条：凹槽 + 强调色填充，可拖动
    private var progressBar: some View {
        VStack(spacing: 4) {
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    NeuSurface(shape: Capsule(), pressed: true, depth: 3)
                    Capsule()
                        .fill(Color.neuAccent)
                        .frame(width: max(6, (geo.size.width - 6) * progress))
                        .padding(3)
                }
                .frame(height: 12)
                .frame(maxHeight: .infinity)          // 视觉 12pt，可点区域 44pt
                .contentShape(Rectangle())
                .gesture(
                    DragGesture(minimumDistance: 0).onChanged { value in
                        progress = min(max(value.location.x / geo.size.width, 0), 1)
                    }
                )
            }
            .frame(height: 44)

            HStack {
                Text(format(progress * duration))
                Spacer()
                Text(format(duration))
            }
            .font(.footnote.monospacedDigit())
            .foregroundStyle(Color.neuSecondary)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("播放进度")
        .accessibilityValue("\(format(progress * duration))，共 \(format(duration))")
        .accessibilityAdjustableAction { direction in
            let step = 10 / duration
            switch direction {
            case .increment: progress = min(progress + step, 1)
            case .decrement: progress = max(progress - step, 0)
            @unknown default: break
            }
        }
    }

    // 上一首 · 播放/暂停 · 下一首
    private var transport: some View {
        HStack(spacing: 30) {
            Button { progress = 0 } label: {
                Image(systemName: "backward.end.fill")
                    .font(.system(size: 20))
                    .frame(width: 62, height: 62)
            }
            .buttonStyle(NeuButtonStyle(shape: Circle(), depth: 7))
            .accessibilityLabel("上一首")

            Button { isPlaying.toggle() } label: {
                Image(systemName: isPlaying ? "pause.fill" : "play.fill")
                    .font(.system(size: 28))
                    .foregroundStyle(Color.neuAccent)
                    .frame(width: 88, height: 88)
            }
            .buttonStyle(NeuButtonStyle(shape: Circle(), isOn: isPlaying, depth: 10))
            .accessibilityLabel(isPlaying ? "暂停" : "播放")

            Button { progress = 0 } label: {
                Image(systemName: "forward.end.fill")
                    .font(.system(size: 20))
                    .frame(width: 62, height: 62)
            }
            .buttonStyle(NeuButtonStyle(shape: Circle(), depth: 7))
            .accessibilityLabel("下一首")
        }
    }

    // 随机 · 循环：开启时保持凹陷
    private var modeToggles: some View {
        HStack(spacing: 18) {
            modeButton("随机", systemImage: "shuffle", isOn: $shuffle)
            modeButton("循环", systemImage: "repeat", isOn: $repeatOn)
        }
    }

    private func modeButton(_ title: String, systemImage: String, isOn: Binding<Bool>) -> some View {
        Button { isOn.wrappedValue.toggle() } label: {
            Label(title, systemImage: systemImage)
                .font(.subheadline.weight(.medium))
                .foregroundStyle(isOn.wrappedValue ? Color.neuAccent : Color.neuSecondary)
                .frame(maxWidth: .infinity)
                .frame(height: 54)
        }
        .buttonStyle(NeuButtonStyle(shape: Capsule(), isOn: isOn.wrappedValue, depth: 6))
        .accessibilityAddTraits(isOn.wrappedValue ? .isSelected : [])
    }

    // MARK: 播放逻辑（仅演示）

    private func advance() {
        guard isPlaying else { return }
        progress += 1 / duration
        if progress >= 1 {
            if repeatOn {
                progress = 0
            } else {
                progress = 1
                isPlaying = false
            }
        }
    }

    private func format(_ seconds: Double) -> String {
        let s = Int(seconds.rounded())
        return String(format: "%d:%02d", s / 60, s % 60)
    }
}

// MARK: - 预览

#Preview("浅色") {
    NeuPlayerView()
}

#Preview("深色") {
    NeuPlayerView()
        .preferredColorScheme(.dark)
}
