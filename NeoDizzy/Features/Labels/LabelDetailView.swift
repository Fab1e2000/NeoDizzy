import SwiftUI

/// 社团页：简介、pack 和全部作品。关注社团在 M5 接入。
struct LabelDetailView: View {
    let name: String
    @State private var page: Loadable<LabelPage>

    init(name: String) {
        self.name = name
        _page = State(initialValue: Loadable { try await DizzyPages.shared.label(name: name) })
    }

    var body: some View {
        LoadableContent(state: page, webURL: DizzyURL.label(name)) { label in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 24) {
                    header(label)
                    FollowLabelButton(name: name, onChanged: { await page.load() })
                    if !label.description.isEmpty {
                        ExpandableText(title: "简介", text: label.description)
                    }
                    if !label.packs.isEmpty {
                        SectionHeading(title: "pack")
                        LazyVGrid(columns: DizzyGrid.columns, alignment: .leading, spacing: 22) {
                            ForEach(label.packs) { PackCard(pack: $0) }
                        }
                    }
                    SectionHeading(title: "作品 \(label.discs.count)")
                    DiscGrid(discs: label.discs, showsLabel: false)
                    ForEach(label.history, id: \.self) { line in
                        Text(line)
                            .font(.caption)
                            .foregroundStyle(DizzyPalette.mutedText)
                    }
                }
                .padding(.horizontal, 20)
                .padding(.vertical, 16)
            }
            .refreshable { await page.load() }
        }
        .dizzyPageBackground()
        .safeAreaPadding(.top, 5)
        .navigationTitle(name)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Link(destination: DizzyURL.label(name)) {
                    Image(systemName: "safari")
                }
                .accessibilityLabel("在网页中打开")
            }
        }
    }

    private func header(_ label: LabelPage) -> some View {
        HStack(spacing: 16) {
            ArtworkImage(url: label.coverURL, cornerRadius: 16)
                .frame(width: 96)
            VStack(alignment: .leading, spacing: 6) {
                Text(label.name)
                    .font(.title2.bold())
                    .foregroundStyle(DizzyPalette.text)
                    .lineLimit(2)
                if let followers = label.followerCount {
                    Text("\(followers) 人关注")
                        .font(.subheadline)
                        .foregroundStyle(DizzyPalette.mutedText)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}
