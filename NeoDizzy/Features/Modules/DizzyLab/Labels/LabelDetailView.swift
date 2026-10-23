import SwiftUI

/// 社团页：头像与关注、简介、pack 和全部作品，样式与网易云歌手页相同。
struct LabelDetailView: View {
    let name: String
    @State private var page: Loadable<LabelPage>

    init(name: String) {
        self.name = name
        _page = State(initialValue: Loadable { try await DizzyPages.shared.label(name: name) })
    }

    var body: some View {
        LoadableContent(state: page, skeleton: .profile, skeletonIsPage: true) { label in
            AlbumDetailScrollView(artworkURL: label.coverURL) { content(label) }
                .refreshable { await page.load() }
        }
        .navigationTitle("")
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(.hidden, for: .navigationBar)
    }

    /// 与网易云歌手页同一套外观：背景取社团头像颜色，依次是头像与关注、最新作品、全部作品、pack、简介。
    private func content(_ label: LabelPage) -> some View {
        let subtitle = ([label.followerCount.map { "\($0) 人关注" }, "\(label.discs.count) 张作品"].compactMap { $0 })
            .joined(separator: " · ")
        return LazyVStack(alignment: .leading, spacing: 28) {
            ProfileHero(artworkURL: label.coverURL, title: label.name, subtitle: subtitle, cornerRadius: 28) {
                HStack(spacing: 12) {
                    FollowLabelButton(name: name, onChanged: { await page.load() })
                        .controlSize(.large)
                        .buttonBorderShape(.capsule)
                    ShareLink(item: DizzyURL.label(name)) {
                        Image(systemName: "square.and.arrow.up").frame(width: 30, height: 30)
                    }
                    .buttonStyle(.bordered)
                    .buttonBorderShape(.circle)
                    .controlSize(.large)
                    .accessibilityLabel("分享")
                }
                .tint(DizzyPalette.text)
            }
            if let latest = label.discs.first {
                VStack(alignment: .leading, spacing: 12) {
                    ProfileSectionHeader(title: "最新作品")
                    NavigationLink(value: AppRoute.disc(id: latest.id)) {
                        HStack(spacing: 14) {
                            ArtworkImage(url: latest.coverURL, cornerRadius: 8).frame(width: 92, height: 92)
                            VStack(alignment: .leading, spacing: 4) {
                                Text(latest.title).font(.headline).foregroundStyle(.primary).lineLimit(2)
                                if !latest.tags.isEmpty {
                                    Text(latest.tags.prefix(3).joined(separator: " · ")).font(.subheadline).foregroundStyle(.secondary).lineLimit(1)
                                }
                            }
                            Spacer(minLength: 0)
                        }
                        .padding(12)
                        .background(.primary.opacity(0.08), in: .rect(cornerRadius: 14))
                        .contentShape(.rect(cornerRadius: 14))
                    }
                    .buttonStyle(.plain)
                    .padding(.horizontal, 20)
                }
            }
            if label.discs.count > 1 {
                VStack(alignment: .leading, spacing: 12) {
                    ProfileSectionHeader(title: "全部作品", allTitle: "全部 \(label.discs.count) 张") {
                        LabelDiscsPage(name: label.name, discs: label.discs)
                    }
                    shelf(label.discs)
                }
            }
            if !label.packs.isEmpty {
                VStack(alignment: .leading, spacing: 12) {
                    ProfileSectionHeader(title: "pack")
                    ScrollView(.horizontal) {
                        LazyHStack(alignment: .top, spacing: 14) {
                            ForEach(label.packs) { PackCard(pack: $0).frame(width: 156) }
                        }
                    }
                    .scrollIndicators(.hidden)
                    .contentMargins(.horizontal, 20, for: .scrollContent)
                }
            }
            if !label.description.isEmpty {
                ExpandableText(title: "简介", text: label.description).padding(.horizontal, 20)
            }
            if !label.history.isEmpty {
                Text(label.history.joined(separator: "\n"))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 20)
            }
        }
        .padding(.bottom, 32)
    }

    private func shelf(_ discs: [DiscSummary]) -> some View {
        ScrollView(.horizontal) {
            LazyHStack(alignment: .top, spacing: 14) {
                ForEach(discs.prefix(20)) { disc in
                    NavigationLink(value: AppRoute.disc(id: disc.id)) {
                        DiscCard(disc: disc, showsLabel: false, reservesTitleLines: true).frame(width: 156)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .scrollIndicators(.hidden)
        .contentMargins(.horizontal, 20, for: .scrollContent)
    }
}

/// 「全部 N 张」：社团的全部作品网格。
struct LabelDiscsPage: View {
    let name: String
    let discs: [DiscSummary]

    var body: some View {
        ScrollView {
            DiscGrid(discs: discs, showsLabel: false)
                .padding(.horizontal, 20).padding(.vertical, 8)
        }
        .dizzyPageBackground()
        .navigationTitle("\(name) · 作品")
        .navigationBarTitleDisplayMode(.inline)
    }
}
