import SwiftUI

struct DiscoverSearchResults: View {
    let model: SearchModel
    var body: some View {
        if let keyword = model.keyword, let discs = model.discs {
            if !model.labels.isEmpty {
                SectionHeading(title: "社团")
                ForEach(model.labels) { label in
                    NavigationLink(value: AppRoute.label(name: label.name)) {
                        SearchResultRow(
                            coverURL: label.coverURL,
                            title: label.name,
                            subtitle: nil,
                            excerpt: label.description
                        )
                    }
                    .buttonStyle(.plain)
                }
            }
            if !model.users.isEmpty {
                SectionHeading(title: "用户")
                ForEach(model.users) { CommunityUserLink(user: $0) }
            }
            SectionHeading(title: "作品")
            PagedContent(list: discs, webURL: DizzyURL.search(keyword), emptyMessage: "没有找到相关作品。") { results in
                ForEach(results) { result in
                    NavigationLink(value: AppRoute.disc(id: result.disc.id)) {
                        SearchResultRow(
                            coverURL: result.disc.coverURL,
                            title: result.disc.title,
                            subtitle: result.disc.labelName,
                            excerpt: result.excerpt
                        )
                        .prefetchAlbumArtwork(url: result.disc.coverURL)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }
}

/// 搜索结果的一行：封面、标题、社团和一段介绍。
private struct SearchResultRow: View {
    let coverURL: URL?
    let title: String
    let subtitle: String?
    let excerpt: String

    var body: some View {
        HStack(alignment: .top, spacing: 14) {
            ArtworkImage(url: coverURL, cornerRadius: 10)
                .frame(width: 72)
            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.headline)
                    .foregroundStyle(DizzyPalette.text)
                    .lineLimit(2)
                if let subtitle, !subtitle.isEmpty {
                    Text(subtitle)
                        .font(.subheadline)
                        .foregroundStyle(DizzyPalette.accent)
                        .lineLimit(1)
                }
                if !excerpt.isEmpty {
                    Text(excerpt)
                        .font(.caption)
                        .foregroundStyle(DizzyPalette.mutedText)
                        .lineLimit(2)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .contentShape(.rect)
    }
}
