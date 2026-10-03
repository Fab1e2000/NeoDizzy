import AppKit

/// 空格键播放 / 暂停，与 Music 相同。只在没有文字输入焦点、没有弹出面板时生效，
/// 不使用菜单快捷键，避免在搜索框和表单里吞掉空格。
final class PlaybackKeyMonitor {
    private var monitor: Any?

    init(player: PlayerStore) {
        monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak player] event in
            guard Self.isPlainSpace(event) else { return event }
            // 本地事件监视器总在主线程调用。
            nonisolated(unsafe) let event = event
            let handled = MainActor.assumeIsolated {
                guard let player, let window = event.window, window.attachedSheet == nil, !window.isSheet,
                      !(window.firstResponder is NSText), player.currentTrack != nil else { return false }
                player.togglePlayback()
                return true
            }
            return handled ? nil : event
        }
    }

    deinit {
        if let monitor { NSEvent.removeMonitor(monitor) }
    }

    nonisolated private static func isPlainSpace(_ event: NSEvent) -> Bool {
        let modifiers = event.modifierFlags.intersection(.deviceIndependentFlagsMask).subtracting([.capsLock, .numericPad, .function])
        return event.keyCode == 49 && modifiers.isEmpty && !event.isARepeat
    }
}
