import SwiftUI
import AVKit

struct AirPlayButton: UIViewRepresentable {
    var opacity: Double = 0.72
    func makeUIView(context: Context) -> AVRoutePickerView {
        let picker = AVRoutePickerView()
        picker.tintColor = UIColor.white.withAlphaComponent(opacity)
        picker.prioritizesVideoDevices = false
        return picker
    }

    /// 播放页固定深色，用主题色的深色档，不随窗口外观取浅色档。
    func updateUIView(_ picker: AVRoutePickerView, context: Context) {
        picker.tintColor = UIColor.white.withAlphaComponent(opacity)
        picker.activeTintColor = UIColor(DizzyPalette.accentOnDark)
    }
}

