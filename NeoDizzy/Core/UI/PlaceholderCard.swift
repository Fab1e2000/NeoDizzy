import SwiftUI

/// 尚未接入数据的区域：图标、标题和一句说明。
struct PlaceholderCard: View {
    let systemImage: String
    let title: LocalizedStringKey
    let message: LocalizedStringKey

    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: systemImage)
                .font(.system(size: 36))
                .foregroundStyle(DizzyPalette.accent)
            Text(title)
                .font(.headline)
                .foregroundStyle(DizzyPalette.text)
            Text(message)
                .font(.subheadline)
                .foregroundStyle(DizzyPalette.mutedText)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 40)
        .padding(.horizontal, 24)
        .background(DizzyPalette.surface, in: .rect(cornerRadius: 20))
    }
}
