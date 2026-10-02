import SwiftUI

/// App Store-style filled capsule, with a native text field and search keyboard.
struct DiscoverSearchBar: View {
    @Binding var text: String
    let submit: () -> Void
    @FocusState private var isFocused: Bool
    @ScaledMetric(relativeTo: .body) private var iconSize = 20.0

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: iconSize, weight: .regular))
                .foregroundStyle(.primary)
                .accessibilityHidden(true)
            TextField("搜索专辑、社团、用户", text: $text)
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
        .onTapGesture { isFocused = true }
    }
}
