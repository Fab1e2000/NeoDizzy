import SwiftUI
import AVKit

/// 隔空播放按钮。输出是蓝牙时图标换成 AirPods，点按仍弹出系统的输出设备选择。
struct AirPlayButton: View {
    var opacity: Double = 0.72
    @State private var route = AudioOutputRoute()

    var body: some View {
        ZStack {
            AirPlayRoutePicker(opacity: opacity, hidesGlyph: route.symbolName != nil)
            if let symbolName = route.symbolName {
                Image(systemName: symbolName)
                    .font(.system(size: 18, weight: .regular))
                    .foregroundStyle(.white.opacity(opacity))
                    .allowsHitTesting(false)
                    .accessibilityHidden(true)
            }
        }
    }
}

/// 当前音频输出是不是蓝牙。系统拿不到耳机型号（第三方耳机更是什么都没有），所以不区分型号，
/// 蓝牙输出一律用 AirPods 图标。
@MainActor @Observable
private final class AudioOutputRoute {
    private(set) var symbolName: String?
    @ObservationIgnored private var observer: NSObjectProtocol?

    init() {
        refresh()
        observer = NotificationCenter.default.addObserver(
            forName: AVAudioSession.routeChangeNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.refresh() }
        }
    }

    deinit {
        if let observer { NotificationCenter.default.removeObserver(observer) }
    }

    private func refresh() {
        let bluetooth: Set<AVAudioSession.Port> = [.bluetoothA2DP, .bluetoothLE, .bluetoothHFP]
        let isBluetooth = AVAudioSession.sharedInstance().currentRoute.outputs
            .contains { bluetooth.contains($0.portType) }
        let symbol = isBluetooth ? "airpods" : nil
        if symbolName != symbol { symbolName = symbol }
    }
}

private struct AirPlayRoutePicker: UIViewRepresentable {
    let opacity: Double
    /// 用自己画的 AirPods 图标时，把系统图标藏起来，只保留点按功能。
    let hidesGlyph: Bool

    func makeUIView(context: Context) -> AVRoutePickerView {
        let picker = AVRoutePickerView()
        picker.prioritizesVideoDevices = false
        return picker
    }

    /// 播放页固定深色，用主题色的深色档，不随窗口外观取浅色档。
    func updateUIView(_ picker: AVRoutePickerView, context: Context) {
        picker.tintColor = hidesGlyph ? .clear : UIColor.white.withAlphaComponent(opacity)
        picker.activeTintColor = hidesGlyph ? .clear : UIColor(DizzyPalette.accentOnDark)
    }
}
