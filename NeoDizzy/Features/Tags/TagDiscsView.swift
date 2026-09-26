import SwiftUI

/// 某个标签下的全部作品，每页 24 张。
struct TagDiscsView: View {
    let tag: String
    @State private var discs: PagedList<DiscSummary>

    init(tag: String) {
        self.tag = tag
        _discs = State(initialValue: PagedList { page in try await DizzyPages.shared.tag(tag, page: page) })
    }

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 20) {
                PagedContent(list: discs, webURL: DizzyURL.tag(tag)) { discs in
                    DiscGrid(discs: discs)
                }
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 16)
        }
        .refreshable { await discs.reload() }
        .dizzyPageBackground()
        .navigationTitle("#\(tag)")
        .navigationBarTitleDisplayMode(.inline)
    }
}
