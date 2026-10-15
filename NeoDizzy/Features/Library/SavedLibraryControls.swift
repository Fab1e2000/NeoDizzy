import SwiftUI

/// 专辑、歌单页工具栏上的「加入资料库 / 已在资料库」开关。
struct SavedLibraryToggle: View {
    let item: SavedLibraryItem
    @Environment(SavedLibraryStore.self) private var saved

    var body: some View {
        let added = saved.contains(item.kind, providerID: item.providerID, itemID: item.itemID)
        Button(added ? "从资料库移除" : "加入资料库", systemImage: added ? "rectangle.stack.fill" : "rectangle.stack.badge.plus") {
            saved.toggle(item)
        }
        .sensoryFeedback(.success, trigger: added) { _, isAdded in isAdded }
    }
}

extension SavedLibraryStore {
    /// 歌曲菜单里的「加入资料库 / 从资料库移除」。
    func rowAction(for item: SavedLibraryItem) -> AlbumRowAction {
        let added = contains(item.kind, providerID: item.providerID, itemID: item.itemID)
        return AlbumRowAction(id: "library", title: added ? "从资料库移除" : "加入资料库",
                              systemImage: added ? "rectangle.stack.badge.minus" : "rectangle.stack.badge.plus") { [weak self] in
            self?.toggle(item)
        }
    }
}
