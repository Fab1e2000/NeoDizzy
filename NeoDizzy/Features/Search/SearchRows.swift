import SwiftUI

// Adapted from MeloX Features/Search/SearchView.swift (GPL-3.0).

/// 专辑、歌单、歌手、社团的一行，尺寸与封面式歌曲行一致：44pt 封面（歌手、社团为圆形）、
/// 名称和一行说明，最少 60pt 高，行尾是箭头；放进 `List` 时由系统画箭头，传 `showsChevron: false`。
struct SearchMediaRow: View {
    let title: String
    let subtitle: String?
    let artworkURL: URL?
    var circular = false
    var showsChevron = true

    var body: some View {
        HStack(spacing: 12) {
            ArtworkImage(url: artworkURL, cornerRadius: circular ? 1_000 : 6)
                .frame(width: 44, height: 44)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.body)
                    .foregroundStyle(DizzyPalette.text)
                    .lineLimit(1)
                if let subtitle, !subtitle.isEmpty {
                    Text(subtitle)
                        .font(.footnote)
                        .foregroundStyle(DizzyPalette.mutedText)
                        .lineLimit(1)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            if showsChevron {
                Image(systemName: "chevron.right")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(.tertiary)
                    .accessibilityHidden(true)
            }
        }
        .padding(.vertical, 8)
        .frame(minHeight: 60)
        .contentShape(.rect)
    }
}

/// 统一搜索里的一组结果：标题行，下面是像分组列表一样的圆角卡片。
struct SearchGroup<Content: View>: View {
    let title: String
    var allResults: AppRoute?
    @ViewBuilder var content: () -> Content

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            SearchSectionHeader(title: title, allResults: allResults)
                .padding(.horizontal, 4)
            VStack(alignment: .leading, spacing: 0) { content() }
                .padding(.horizontal, 16)
                .background(DizzyPalette.surface, in: .rect(cornerRadius: 12))
        }
    }
}

/// 卡片里的一句说明（正在搜索、没有结果、失败、未登录）：上下留白，与行同宽。
struct SearchCardRow<Content: View>: View {
    @ViewBuilder var content: () -> Content

    var body: some View {
        content()
            .padding(.vertical, 8)
            .frame(maxWidth: .infinity, alignment: .leading)
    }
}
