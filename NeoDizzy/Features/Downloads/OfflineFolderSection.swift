import SwiftUI
import UniformTypeIdentifiers

/// 通过系统文件选择器保留文件夹授权，用于下载目标目录。
///
/// 同一页面里只能有一个 `fileImporter`：嵌在已有文件选择器的页面里（扫描目录页）时，
/// 传入 `chooseFolder` 交给外层的选择器，本区块不再挂自己的选择器；否则选择器能打开，
/// 但点「打开」后结果回不来。单独使用时（下载面板）不传，由本区块自己弹出。
struct OfflineFolderSection: View {
    var chooseFolder: (() -> Void)?
    @Environment(OfflineLibraryStore.self) private var offline
    @Environment(DownloadStore.self) private var downloads
    @State private var isChoosingFolder = false
    @State private var isSelectingFolder = false
    @State private var selectionError: String?

    private var isBusy: Bool { offline.isScanning || isSelectingFolder }
    private var hasActiveDownloads: Bool { downloads.jobs.contains(where: \.isActive) }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label(offline.folderName ?? "选择下载目录", systemImage: "folder")
                .font(.headline)
                .foregroundStyle(DizzyPalette.text)
            Text(offline.folderName == nil
                 ? "选择「文件」中的文件夹，用来保存下载的专辑。"
                 : "下载的音乐保存在此文件夹，并自动加入本地库。")
                .font(.caption)
                .foregroundStyle(DizzyPalette.mutedText)
            HStack(spacing: 12) {
                Button(offline.folderName == nil ? "选择文件夹" : "更换文件夹", systemImage: "folder.badge.plus") {
                    if let chooseFolder { chooseFolder() } else { isChoosingFolder = true }
                }
                .buttonStyle(.bordered)
                .disabled(isBusy || hasActiveDownloads)
                .accessibilityHint(hasActiveDownloads ? "请先等待下载完成或取消下载" : "打开系统文件选择器")

                if offline.folderName != nil {
                    Button("扫描", systemImage: "arrow.clockwise") {
                        Task { await offline.scan() }
                    }
                    .buttonStyle(.bordered)
                    .disabled(isBusy)
                    .accessibilityLabel("重新扫描本地库")
                }
                if isBusy {
                    ProgressView()
                        .accessibilityLabel("正在读取音乐文件夹")
                }
            }
            if let issue = selectionError ?? offline.issue {
                Label(issue, systemImage: "exclamationmark.triangle")
                    .font(.caption)
                    .foregroundStyle(DizzyPalette.accent)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(DizzyPalette.surface, in: .rect(cornerRadius: 14))
        .fileImporter(isPresented: $isChoosingFolder, allowedContentTypes: [.folder]) { result in
            switch result {
            case .success(let url):
                isSelectingFolder = true
                selectionError = nil
                Task {
                    defer { isSelectingFolder = false }
                    selectionError = await Self.selectDownloadFolder(url, in: offline)
                }
            case .failure(let error):
                selectionError = error.localizedDescription
            }
        }
    }

    /// 保存下载目录的授权；失败时返回要显示的错误信息。
    static func selectDownloadFolder(_ url: URL, in offline: OfflineLibraryStore) async -> String? {
        do {
            try await offline.selectFolder(url)
            return nil
        } catch is CancellationError {
            return nil
        } catch {
            return error.localizedDescription
        }
    }
}
