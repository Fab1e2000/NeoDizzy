import SwiftUI

/// The module's most-used entry: a full-width card with an icon tile, a title and a one-line description.
struct ModulePrimaryShortcut: View {
    enum Trailing { case play, chevron }

    let title: String
    let subtitle: String
    var systemImage: String = ""
    /// Draws today's date in the icon tile instead of the symbol (NetEase daily picks).
    var showsToday = false
    var trailing: Trailing = .chevron
    var isLoading = false
    @ScaledMetric(relativeTo: .title3) private var tileSize = 44.0

    var body: some View {
        HStack(spacing: 12) {
            ZStack {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(DizzyPalette.accent.opacity(0.16))
                icon.foregroundStyle(DizzyPalette.accent)
            }
            .frame(width: tileSize, height: tileSize)
            .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.headline).foregroundStyle(DizzyPalette.text)
                Text(subtitle).font(.footnote).foregroundStyle(DizzyPalette.mutedText).lineLimit(1)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            Group {
                switch trailing {
                case .play: Image(systemName: "play.fill").font(.body).foregroundStyle(DizzyPalette.text)
                case .chevron: Image(systemName: "chevron.right").font(.footnote.weight(.semibold)).foregroundStyle(.tertiary)
                }
            }
            .accessibilityHidden(true)
        }
        .padding(.leading, 12)
        .padding(.trailing, 16)
        .padding(.vertical, 12)
        .background(DizzyPalette.surface, in: .rect(cornerRadius: 18, style: .continuous))
        .contentShape(.rect(cornerRadius: 18))
    }

    @ViewBuilder private var icon: some View {
        if isLoading {
            ProgressView().tint(DizzyPalette.accent)
        } else if showsToday {
            VStack(spacing: 0) {
                Text(Date.now, format: .dateTime.month(.abbreviated))
                    .font(.system(size: tileSize * 0.2, weight: .bold))
                Text(verbatim: "\(Calendar.current.component(.day, from: .now))")
                    .font(.system(size: tileSize * 0.45, weight: .bold))
                    .monospacedDigit()
            }
        } else {
            Image(systemName: systemImage).font(.title3.weight(.semibold))
        }
    }
}

/// A smaller entry under the primary card: icon and title in one rounded button, three to a row.
struct ModuleSecondaryShortcut: View {
    let title: String
    let systemImage: String
    var isLoading = false

    var body: some View {
        HStack(spacing: 6) {
            Group {
                if isLoading { ProgressView().controlSize(.small) }
                else { Image(systemName: systemImage).font(.subheadline.weight(.semibold)) }
            }
            .foregroundStyle(DizzyPalette.accent)
            .accessibilityHidden(true)
            Text(title)
                .font(.subheadline)
                .foregroundStyle(DizzyPalette.text)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
        }
        .padding(.horizontal, 8)
        .frame(maxWidth: .infinity, minHeight: 44)
        .background(DizzyPalette.surface, in: .rect(cornerRadius: 12, style: .continuous))
        .contentShape(.rect(cornerRadius: 12))
    }
}

/// Primary card on top, the other entries in one row underneath (stacked at accessibility text sizes).
struct ModuleShortcutPanel<Primary: View, Secondary: View>: View {
    @Environment(\.dynamicTypeSize) private var typeSize
    @ViewBuilder var primary: Primary
    @ViewBuilder var secondary: Secondary

    var body: some View {
        VStack(spacing: 8) {
            primary
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 8),
                                     count: typeSize.isAccessibilitySize ? 1 : 3), spacing: 8) {
                secondary
            }
        }
    }
}
