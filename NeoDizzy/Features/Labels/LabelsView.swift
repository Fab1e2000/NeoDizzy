import SwiftUI

struct LabelsView: View {
    @State private var labels = PagedList { page in try await DizzyAPI.shared.labels(page: page) }

    var body: some View {
        MainTabPage(tab: .labels, onRefresh: { await labels.reload() }) {
            PagedContent(list: labels, webURL: DizzyURL.page("/label/")) { labels in
                ForEach(labels) { label in
                    NavigationLink(value: AppRoute.label(name: label.name)) {
                        LabelRow(label: label)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }
}

/// 社团列表的一行：封面、名称、简介和最近几张作品。
private struct LabelRow: View {
    let label: LabelSummary

    var body: some View {
        HStack(alignment: .top, spacing: 14) {
            AvatarImage(url: label.coverURL, size: 64)
            VStack(alignment: .leading, spacing: 6) {
                Text(label.name)
                    .font(.headline)
                    .foregroundStyle(DizzyPalette.text)
                    .lineLimit(1)
                if !label.description.isEmpty {
                    Text(label.description)
                        .font(.caption)
                        .foregroundStyle(DizzyPalette.mutedText)
                        .lineLimit(2)
                }
                if !label.recentDiscs.isEmpty {
                    HStack(spacing: 6) {
                        ForEach(label.recentDiscs.prefix(4)) { disc in
                            ArtworkImage(url: disc.coverURL, cornerRadius: 6)
                                .frame(width: 40)
                        }
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            Image(systemName: "chevron.right")
                .font(.footnote.weight(.semibold))
                .foregroundStyle(DizzyPalette.mutedText)
                .padding(.top, 4)
        }
        .padding(12)
        .background(DizzyPalette.surface, in: .rect(cornerRadius: 16))
        .contentShape(.rect)
    }
}
