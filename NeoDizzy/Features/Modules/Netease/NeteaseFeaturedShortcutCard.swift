import SwiftUI

/// 网易云首页的两个常用入口，共享尺寸与层级，分别强调播放和每日更新。
struct NeteaseFeaturedShortcutCard: View {
    enum Kind { case radio, daily }
    let kind: Kind
    var isLoading = false
    @ScaledMetric(relativeTo: .title2) private var iconSize = 46.0

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            HStack(alignment: .top) {
                ZStack {
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .fill(DizzyPalette.accent.opacity(kind == .radio ? 0.16 : 0.09))
                    if kind == .radio {
                        Image(systemName: "dot.radiowaves.left.and.right")
                            .font(.title2.weight(.semibold))
                    } else {
                        VStack(spacing: 0) {
                            Text(Date.now, format: .dateTime.month(.abbreviated))
                                .font(.system(size: iconSize * 0.20, weight: .semibold))
                            Text(verbatim: "\(Calendar.current.component(.day, from: .now))")
                                .font(.system(size: iconSize * 0.43, weight: .bold, design: .rounded))
                                .monospacedDigit()
                        }
                    }
                }
                .foregroundStyle(DizzyPalette.accent)
                .frame(width: iconSize, height: iconSize)
                Spacer(minLength: 4)
                ZStack {
                    Circle().fill(DizzyPalette.surface.opacity(0.8))
                    if isLoading {
                        ProgressView().controlSize(.small).tint(DizzyPalette.accent)
                    } else {
                        Image(systemName: kind == .radio ? "play.fill" : "arrow.up.right")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(DizzyPalette.accent)
                    }
                }
                .frame(width: 28, height: 28)
            }
            .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 5) {
                Text(kind == .radio ? "私人 FM" : "每日推荐")
                    .font(.headline).foregroundStyle(DizzyPalette.text)
                Text(kind == .radio ? "随心听，遇见下一首" : "每天 6 点，为你更新")
                    .font(.caption).foregroundStyle(DizzyPalette.mutedText)
                    .lineLimit(2, reservesSpace: true)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background {
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .fill(DizzyPalette.surface)
                .overlay {
                    RoundedRectangle(cornerRadius: 22, style: .continuous)
                        .fill(LinearGradient(colors: [DizzyPalette.accent.opacity(kind == .radio ? 0.12 : 0.05), .clear],
                                             startPoint: .topLeading, endPoint: .bottomTrailing))
                }
        }
        .contentShape(.rect(cornerRadius: 22))
    }
}
