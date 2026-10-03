import Foundation
import Observation

@Observable
final class SearchModel {
    var query = ""
    private(set) var keyword: String?
    /// 社团只在第一页结果里。
    private(set) var users: [CommunityUser] = []
    private(set) var labels: [SearchLabel] = []
    private(set) var discs: PagedList<SearchDisc>?

    /// 只在按下搜索键时请求，不跟随每次输入。
    func submit() {
        let keyword = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !keyword.isEmpty, keyword != self.keyword else { return }
        self.keyword = keyword
        labels = []
        users = []
        discs = PagedList { [weak self] page in
            let results = try await DizzyPages.shared.search(keyword, page: page)
            if page == 1, self?.keyword == keyword { self?.labels = results.labels; self?.users = results.users }
            return Page(items: results.discs, hasMore: results.hasMore)
        }
    }

    func clear() {
        keyword = nil
        labels = []
        users = []
        discs = nil
    }
}
