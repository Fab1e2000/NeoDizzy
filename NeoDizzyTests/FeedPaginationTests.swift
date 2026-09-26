import Foundation
import Testing
@testable import NeoDizzy

struct FeedPaginationTests {
    private func group(_ id: Int, date: String, name: String = "社团") -> FeedGroup {
        FeedGroup(labelID: id, labelName: name, labelCoverURL: nil, addDate: date, discs: [])
    }

    @Test func sameLabelAppearsOnceWithinAndAcrossPages() async {
        let latest = group(1, date: "2026-09-26")
        let list = PagedList<FeedGroup> { page in
            if page == 1 {
                return Page(items: [latest, group(1, date: "2026-09-25"), group(2, date: "2026-09-24")], hasMore: true)
            }
            return Page(items: [group(1, date: "2026-09-23"), group(3, date: "2026-09-22"), group(3, date: "2026-09-21")], hasMore: false)
        }
        await list.loadMore()
        #expect(list.items.map(\.labelID) == [1, 2])
        await list.loadMore()
        #expect(list.items.map(\.labelID) == [1, 2, 3])
        #expect(list.items.first == latest)
        #expect(!list.hasMore)
        await list.reload()
        #expect(list.items.map(\.labelID) == [1, 2])
    }

    @Test func duplicateOnlyPageDoesNotEndPagination() async {
        let list = PagedList<FeedGroup> { page in
            Page(items: [group(page < 3 ? 1 : 2, date: "page-\(page)")], hasMore: page < 3)
        }
        await list.loadMore()
        await list.loadMore()
        #expect(list.items.count == 1)
        #expect(list.loadedPages == 2)
        #expect(list.hasMore)
        await list.loadMore()
        #expect(list.items.map(\.labelID) == [1, 2])
        #expect(!list.hasMore)
    }
}
