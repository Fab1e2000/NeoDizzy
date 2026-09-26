import SwiftUI
import UniformTypeIdentifiers

/// 通过系统文件选择器保留文件夹授权，音乐库与下载面板共用。
struct OfflineFolderSection: View {
    @Environment(OfflineLibraryStore.self) private var offline
    @Environment(DownloadStore.self) private var downloads
    @State private var isChoosingFolder = false
    @State private var isSelectingFolder = false
    @State private var selectionError: String?

    private var isBusy: Bool { offline.isScanning || isSelectingFolder }
    private var hasActiveDownloads: Bool { downloads.jobs.contains(where: \.isActive) }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label(offline.folderName ?? "选择音乐文件夹", systemImage: "folder")
                .font(.headline)
                .foregroundStyle(DizzyPalette.text)
            Text(offline.folderName == nil
                 ? "选择「文件」中的文件夹，用来保存下载和读取本地音乐。"
                 : "下载的音乐保存在此文件夹，下拉或轻点扫描可更新本地专辑。")
                .font(.caption)
                .foregroundStyle(DizzyPalette.mutedText)
            HStack(spacing: 12) {
                Button(offline.folderName == nil ? "选择文件夹" : "更换文件夹", systemImage: "folder.badge.plus") {
                    isChoosingFolder = true
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
                    .accessibilityLabel("重新扫描音乐文件夹")
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
                    do {
                        try await offline.selectFolder(url)
                    } catch is CancellationError {
                        return
                    } catch {
                        selectionError = error.localizedDescription
                    }
                }
            case .failure(let error):
                selectionError = error.localizedDescription
            }
        }
    }
}
