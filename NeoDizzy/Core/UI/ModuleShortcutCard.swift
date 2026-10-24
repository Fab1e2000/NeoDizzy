import SwiftUI

/// Two side-by-side entries at the top of a module's home (NetEase, QQ Music).
/// Playback uses theme-tinted glass; daily picks keep a neutral glass surface.
struct FeaturedShortcutCard: View {
    enum Icon { case symbol(String), today }

    let title: String
    let subtitle: String
    let icon: Icon
    var startsPlayback = false
    var isLoading = false
    @ScaledMetric(relativeTo: .title2) private var iconSize = 44.0

    private var ink: Color { startsPlayback ? DizzyPalette.onAccent : .primary }
    private var secondaryInk: Color { startsPlayback ? DizzyPalette.onAccent.opacity(0.85) : .secondary }
    private var iconInk: Color { startsPlayback ? DizzyPalette.onAccent : DizzyPalette.accent }

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            HStack(alignment: .top) {
                iconView.frame(minWidth: iconSize, alignment: .topLeading)
                Spacer(minLength: 4)
                trailing
            }
            // 两张卡片的图标区等高，标题对齐。
            .frame(height: iconSize, alignment: .top)
            .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 4) {
                Text(title).font(.title3.bold()).foregroundStyle(ink)
                Text(subtitle).font(.footnote).foregroundStyle(secondaryInk)
                    .lineLimit(2, reservesSpace: true)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .contentShape(.rect(cornerRadius: 22))
        .glassEffect((startsPlayback ? Glass.regular.tint(DizzyPalette.accentFill) : .regular).interactive(),
                     in: .rect(cornerRadius: 22))
    }

    @ViewBuilder private var iconView: some View {
        switch icon {
        case .symbol(let name):
            Image(systemName: name).font(.title.weight(.medium)).foregroundStyle(iconInk)
        case .today:
            VStack(alignment: .leading, spacing: 0) {
                Text(Date.now, format: .dateTime.month(.abbreviated))
                    .font(.system(size: iconSize * 0.27, weight: .semibold))
                    .foregroundStyle(iconInk)
                Text(verbatim: "\(Calendar.current.component(.day, from: .now))")
                    .font(.system(size: iconSize * 0.55, weight: .bold))
                    .monospacedDigit()
                    .foregroundStyle(ink)
            }
        }
    }

    @ViewBuilder private var trailing: some View {
        if startsPlayback {
            ZStack {
                Circle().fill(ink.opacity(0.12))
                if isLoading {
                    ProgressView().controlSize(.small).tint(ink)
                } else {
                    Image(systemName: "play.fill").font(.caption.weight(.bold)).foregroundStyle(ink)
                }
            }
            .frame(width: 32, height: 32)
        } else {
            Image(systemName: "arrow.up.right").font(.footnote.weight(.semibold)).foregroundStyle(DizzyPalette.mutedText)
                .frame(width: 32, height: 32)
        }
    }
}

/// The module's most-used entry: a full-width card with an icon tile, a title and a one-line description.
/// Uses the same glass surface as `FeaturedShortcutCard`.
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

    private var prominent: Bool { trailing == .play }
    private var ink: Color { prominent ? DizzyPalette.onAccent : .primary }
    private var secondaryInk: Color { prominent ? DizzyPalette.onAccent.opacity(0.85) : .secondary }
    private var iconInk: Color { prominent ? DizzyPalette.onAccent : DizzyPalette.accent }

    var body: some View {
        HStack(spacing: 12) {
            ZStack {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(iconInk.opacity(0.12))
                icon.foregroundStyle(iconInk)
            }
            .frame(width: tileSize, height: tileSize)
            .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.headline).foregroundStyle(ink)
                Text(subtitle).font(.footnote)
                    .foregroundStyle(secondaryInk).lineLimit(1)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            Group {
                switch trailing {
                case .play: Image(systemName: "play.fill").font(.body).foregroundStyle(ink)
                case .chevron: Image(systemName: "chevron.right").font(.footnote.weight(.semibold)).foregroundStyle(.tertiary)
                }
            }
            .accessibilityHidden(true)
        }
        .padding(.leading, 12)
        .padding(.trailing, 16)
        .padding(.vertical, 12)
        .contentShape(.rect(cornerRadius: 18))
        .glassEffect((prominent ? Glass.regular.tint(DizzyPalette.accentFill) : .regular).interactive(),
                     in: .rect(cornerRadius: 18))
    }

    @ViewBuilder private var icon: some View {
        if isLoading {
            ProgressView().tint(iconInk)
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
                .foregroundStyle(.primary)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
        }
        .padding(.horizontal, 8)
        .frame(maxWidth: .infinity, minHeight: 44)
        .contentShape(.rect(cornerRadius: 12))
        .glassEffect(.regular.interactive(), in: .rect(cornerRadius: 12))
    }
}

/// Primary card on top, the other entries in one row underneath (stacked at accessibility text sizes).
struct ModuleShortcutPanel<Primary: View, Secondary: View>: View {
    @Environment(\.dynamicTypeSize) private var typeSize
    @ViewBuilder var primary: Primary
    @ViewBuilder var secondary: Secondary

    var body: some View {
        GlassEffectContainer(spacing: 8) {
            VStack(spacing: 8) {
                primary
                LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 8),
                                         count: typeSize.isAccessibilitySize ? 1 : 3), spacing: 8) {
                    secondary
                }
            }
        }
    }
}
