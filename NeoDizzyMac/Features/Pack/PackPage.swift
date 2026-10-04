import SwiftUI

/// pack：包含的专辑和价格，在网页中购买。
struct PackPage: View {
    let id: String
    @State private var pack: Loadable<PackDetail>

    init(id: String) {
        self.id = id
        _pack = State(initialValue: Loadable { try await DizzyPages.shared.pack(id: id) })
    }

    var body: some View {
        LoadablePage(state: pack, webURL: DizzyURL.pack(id)) { pack in
            PageScroll {
                AlbumHeader(artworkURL: pack.coverURL, title: pack.title,
                            metadata: String(localized: "pack · \(pack.discs.count) 张专辑")) {
                    if let label = pack.labelName {
                        NavigationLink(label, value: AppRoute.label(name: label)).buttonStyle(.plain)
                    }
                } actions: {
                    Link(destination: DizzyURL.pack(id)) {
                        Label(pack.price.map { "在网页中购买 \(PriceTag.yuan($0))" } ?? String(localized: "在网页中购买"), systemImage: "safari")
                    }
                    .buttonStyle(AccentPillButtonStyle())
                } footer: {
                    if let offer = pack.offer { Text(offer).foregroundStyle(.secondary) }
                }
                VStack(alignment: .leading, spacing: 12) {
                    SectionTitle(String(localized: "包含 \(pack.discs.count) 张专辑"))
                    DiscGrid(discs: pack.discs, showsLabel: false)
                }
                if !pack.description.isEmpty {
                    VStack(alignment: .leading, spacing: 8) {
                        SectionTitle(String(localized: "介绍"))
                        ExpandableText(text: pack.description)
                    }
                }
            }
        }
        .navigationTitle(pack.value?.title ?? AppRoute.pack(id: id).title)
        .pageRefresh { await pack.load() }
    }
}
