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

extension View {
    /// 长按出现「从资料库移除」；下载来的专辑另有「删除下载」，两件事分开做。
    /// 会改动平台账号或删除文件时先用系统确认框确认。
    func libraryRemoval(_ removal: LibraryRemoval?, title: String, downloadedAlbumID: String? = nil) -> some View {
        modifier(LibraryRemovalModifier(removal: removal, title: title, downloadedAlbumID: downloadedAlbumID))
    }

    /// 只负责确认和移除；菜单按钮由调用方自己放，按下时把 `isPresented` 设为 true。
    func libraryRemovalConfirmation(_ removal: LibraryRemoval?, title: String, isPresented: Binding<Bool>) -> some View {
        modifier(LibraryRemovalConfirmation(removal: removal, title: title, isPresented: isPresented))
    }
}

private struct LibraryRemovalModifier: ViewModifier {
    let removal: LibraryRemoval?
    let title: String
    let downloadedAlbumID: String?
    @Environment(OfflineLibraryStore.self) private var library
    @State private var confirmingRemoval = false
    @State private var confirmingDeletion = false
    @State private var deletionFailure: String?

    func body(content: Content) -> some View {
        if removal != nil || downloadedAlbumID != nil {
            content
                .contextMenu {
                    if downloadedAlbumID != nil {
                        Button("删除下载", systemImage: "trash", role: .destructive) { confirmingDeletion = true }
                    }
                    if removal != nil {
                        Button(downloadedAlbumID == nil ? "从资料库移除" : "取消收藏",
                               systemImage: "rectangle.stack.badge.minus", role: .destructive) { confirmingRemoval = true }
                    }
                }
                .libraryRemovalConfirmation(removal, title: title, isPresented: $confirmingRemoval)
                .confirmationDialog("删除「\(title)」的下载？", isPresented: $confirmingDeletion, titleVisibility: .visible) {
                    Button("删除下载", role: .destructive, action: deleteDownload)
                    Button("取消", role: .cancel) { }
                } message: {
                    Text("只删除这台设备上的音频文件，账号里的收藏不受影响。此操作无法撤销。")
                }
                .alert("删除失败", item: $deletionFailure) { _ in
                    Button("好", role: .cancel) { }
                } message: { Text($0) }
        } else {
            content
        }
    }

    private func deleteDownload() {
        guard let downloadedAlbumID else { return }
        Task {
            do { try await library.deleteAlbums(ids: [downloadedAlbumID]) }
            catch { deletionFailure = error.localizedDescription }
        }
    }
}

private struct LibraryRemovalConfirmation: ViewModifier {
    let removal: LibraryRemoval?
    let title: String
    @Binding var isPresented: Bool
    @Environment(SavedLibraryStore.self) private var saved
    @Environment(NeteaseStore.self) private var netease
    @Environment(FavoritesStore.self) private var favorites
    @State private var failure: String?

    func body(content: Content) -> some View {
        content
            // 只动 App 里记录的移除直接执行；会改平台账号的先确认。
            .onChange(of: isPresented) { _, presented in
                guard presented, let removal, removal.accountNotice == nil else { return }
                isPresented = false
                remove(removal)
            }
            .confirmationDialog("从资料库移除「\(title)」？", isPresented: dialogPresented, titleVisibility: .visible) {
                Button("从资料库移除", role: .destructive) { if let removal { remove(removal) } }
                Button("取消", role: .cancel) { }
            } message: {
                Text(removal?.accountNotice ?? "")
            }
            .alert("移除失败", item: $failure) { _ in
                Button("好", role: .cancel) { }
            } message: { Text($0) }
    }

    private var dialogPresented: Binding<Bool> {
        Binding(get: { isPresented && removal?.accountNotice != nil }, set: { isPresented = $0 })
    }

    private func remove(_ removal: LibraryRemoval) {
        Task {
            do {
                switch removal {
                case .saved(let id): saved.remove(id: id)
                case .neteaseSong(let id):
                    guard let song = favorites.songs.first(where: { $0.providerID == "netease" && $0.itemID == String(id) }) else { return }
                    try await favorites.setLiked(song.track, false)
                case .neteasePlaylist(let id): try await netease.library.unsubscribePlaylist(id: id)
                case .neteaseAlbum(let id): try await netease.library.unsubscribeAlbum(id: id)
                }
            } catch is CancellationError {
            } catch { failure = error.localizedDescription }
        }
    }
}
