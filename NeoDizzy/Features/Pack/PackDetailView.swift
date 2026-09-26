import SwiftUI

/// pack 页：包含的专辑和价格。原生购买在 M4 接入，目前在网页中购买。
struct PackDetailView: View {
    let id: String
    @State private var pack: Loadable<PackDetail>

    init(id: String) {
        self.id = id
        _pack = State(initialValue: Loadable { try await DizzyPages.shared.pack(id: id) })
    }

    var body: some View {
        LoadableContent(state: pack, webURL: DizzyURL.pack(id)) { pack in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 24) {
                    header(pack)
                    Link(destination: DizzyURL.pack(id)) {
                        Label("在网页中购买", systemImage: "safari")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.large)
                    SectionHeading(title: "包含 \(pack.discs.count) 张专辑")
                    DiscGrid(discs: pack.discs, showsLabel: false)
                    if !pack.description.isEmpty {
                        ExpandableText(title: "介绍", text: pack.description)
                    }
                }
                .padding(.horizontal, 20)
                .padding(.vertical, 16)
            }
        }
        .dizzyPageBackground()
        .navigationTitle(pack.value?.title ?? AppRoute.pack(id: id).title)
        .navigationBarTitleDisplayMode(.inline)
    }

    private func header(_ pack: PackDetail) -> some View {
        VStack(spacing: 10) {
            ArtworkImage(url: pack.coverURL, cornerRadius: 14)
                .frame(maxWidth: 260)
                .padding(.bottom, 8)
            Text(pack.title)
                .font(.title2.bold())
                .foregroundStyle(DizzyPalette.text)
                .multilineTextAlignment(.center)
            if let label = pack.labelName {
                NavigationLink(value: AppRoute.label(name: label)) {
                    Text(label)
                        .font(.headline)
                        .foregroundStyle(DizzyPalette.accent)
                }
                .buttonStyle(.plain)
            }
            if let price = pack.price {
                PriceText(price: .price(price))
            }
            if let offer = pack.offer {
                Text(offer)
                    .font(.caption)
                    .foregroundStyle(DizzyPalette.mutedText)
                    .multilineTextAlignment(.center)
            }
        }
        .frame(maxWidth: .infinity)
    }
}
