import SwiftUI

/// Single-tap playback entry with cancellation, duplicate-tap protection and retry feedback.
struct DiscoveryShortcutButton: View {
    let title: String
    let systemImage: String
    let start: () async throws -> Void
    @State private var starting = false
    @State private var failure: String?
    var body: some View {
        Button { starting = true } label: {
            ModuleShortcutCard(title: starting ? "正在准备…" : title, systemImage: systemImage)
        }
        .buttonStyle(.plain)
        .disabled(starting)
        .accessibilityLabel(title)
        .task(id: starting) {
            guard starting else { return }
            defer { starting = false }
            do { try await start() }
            catch is CancellationError { }
            catch { if !Task.isCancelled { failure = error.localizedDescription } }
        }
        .alert("暂时无法开始播放", isPresented: Binding(get: { failure != nil }, set: { if !$0 { failure = nil } })) {
            Button("重试") { failure = nil; starting = true }
            Button("取消", role: .cancel) { failure = nil }
        } message: { Text(failure ?? "") }
    }
}
