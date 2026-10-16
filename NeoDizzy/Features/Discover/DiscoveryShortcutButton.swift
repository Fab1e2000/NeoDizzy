import SwiftUI

/// Single-tap playback entry with cancellation, duplicate-tap protection and retry feedback.
struct DiscoveryShortcutButton<Label: View>: View {
    let title: String
    /// Receives whether playback is being prepared.
    @ViewBuilder let label: (Bool) -> Label
    let start: () async throws -> Void
    @State private var starting = false
    @State private var failure: String?
    var body: some View {
        Button { starting = true } label: {
            label(starting)
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
