import SwiftUI

/// 某个标签下的全部作品。
struct TagPage: View {
    let tag: String
    @State private var discs: PagedList<DiscSummary>

    init(tag: String) {
        self.tag = tag
        _discs = State(initialValue: PagedList { page in try await DizzyPages.shared.tag(tag, page: page) })
    }

    var body: some View {
        PageScroll(title: "#\(tag)") {
            PagedSection(list: discs, webURL: DizzyURL.tag(tag)) { DiscGrid(discs: $0) }
        }
        .pageRefresh { await discs.reload() }
    }
}
