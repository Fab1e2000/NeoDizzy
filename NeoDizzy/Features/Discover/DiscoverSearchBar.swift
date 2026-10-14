import SwiftUI

/// App Store-style filled capsule, with a native text field and search keyboard.
struct DiscoverSearchBar: View {
    @Binding var text: String
    var placeholder: LocalizedStringKey = "搜索专辑、社团、用户"
    let submit: () -> Void
    @FocusState private var isFocused: Bool
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @ScaledMetric(relativeTo: .body) private var iconSize = 20.0

    private var showsCancel: Bool { isFocused }

    var body: some View {
        HStack(spacing: 10) {
            inputField
            if showsCancel {
                Button {
                    isFocused = false
                    text = ""
                } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: iconSize, weight: .medium))
                        .foregroundStyle(.primary)
                        .frame(width: 44, height: 44)
                        .contentShape(.circle)
                }
                .buttonStyle(.plain)
                .glassEffect(.regular.interactive(), in: .circle)
                .accessibilityLabel("取消搜索")
                .accessibilityHint("收起键盘并返回浏览内容")
                .transition(.opacity)
            }
        }
        .animation(reduceMotion ? nil : .easeInOut(duration: 0.18), value: showsCancel)
        .onReceive(NotificationCenter.default.publisher(for: UIResponder.keyboardDidHideNotification)) { _ in
            // Interactive keyboard dismissal can leave SwiftUI's focus binding set.
            isFocused = false
        }
    }

    private var inputField: some View {
        HStack(spacing: 10) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: iconSize, weight: .regular))
                .foregroundStyle(.primary)
                .accessibilityHidden(true)
            TextField(placeholder, text: $text)
                .font(.body)
                .textFieldStyle(.plain)
                .focused($isFocused)
                .submitLabel(.search)
                .autocorrectionDisabled()
                .textInputAutocapitalization(.never)
                .onSubmit {
                    submit()
                    isFocused = false
                }
            if !text.isEmpty {
                Button {
                    text = ""
                    isFocused = true
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(.secondary)
                        .frame(width: 24, height: 24)
                        .contentShape(.rect)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("清除搜索")
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .frame(minHeight: 44)
        .background(Color(uiColor: .secondarySystemFill), in: .capsule)
        .contentShape(.capsule)

    }
}
