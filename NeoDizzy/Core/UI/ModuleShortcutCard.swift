import SwiftUI

/// 模块入口统一使用 DizzyLab 已有的卡片样式。
struct ModuleShortcutCard: View {
    let title: String
    let systemImage: String
    @ScaledMetric(relativeTo: .title2) private var iconSize = 26.0

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack(alignment: .center) {
                Image(systemName: systemImage)
                    .font(.system(size: iconSize, weight: .medium))
                    .foregroundStyle(DizzyPalette.accent)
                    .frame(height: iconSize)
                Spacer(minLength: 12)
                Image(systemName: "chevron.right")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(DizzyPalette.mutedText)
            }
            .accessibilityHidden(true)

            Text(title)
                .font(.headline)
                .foregroundStyle(DizzyPalette.text)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(DizzyPalette.surface, in: .rect(cornerRadius: 20))
        .contentShape(.rect(cornerRadius: 20))
    }
}
