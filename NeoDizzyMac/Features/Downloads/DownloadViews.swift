import SwiftUI

/// 一个下载任务：名称、状态、进度，以及取消或重试。
struct DownloadJobRow: View {
    let job: DownloadJob
    @Environment(DownloadStore.self) private var downloads
    @Environment(OfflineLibraryStore.self) private var offline
    @Environment(MacAppModel.self) private var model
    @State private var isRetrying = false

    private var retryUnavailableReason: String? {
        if offline.folderName == nil { return String(localized: "请先选择下载目录") }
        if downloads.jobs.contains(where: { $0.discID == job.discID && $0.isGift == job.isGift && $0.isActive }) {
            return String(localized: "这张专辑已有下载任务")
        }
        if offline.isScanning { return String(localized: "请等待文件夹扫描完成") }
        return nil
    }

    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            ArtworkImage(url: job.album.coverURL, cornerRadius: 5)
                .frame(width: 44, height: 44)
            VStack(alignment: .leading, spacing: 4) {
                Button(job.title) { model.navigation.open(.disc(id: job.discID)) }
                    .buttonStyle(.plain)
                    .font(.body.weight(.medium))
                    .lineLimit(1)
                Text("\(job.format.uppercased()) · \(job.statusText)")
                    .font(.callout)
                    .foregroundStyle(job.canRetry ? Color.dizzyGold : .secondary)
                    .lineLimit(2)
                if job.isActive {
                    DownloadProgressBar(job: job)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            if job.isActive {
                Button { downloads.cancel(job) } label: { Image(systemName: "xmark.circle.fill") }
                    .buttonStyle(.borderless)
                    .foregroundStyle(.secondary)
                    .help("取消下载")
                    .accessibilityLabel("取消下载 \(job.title)")
            } else if job.canRetry {
                Button("重试") {
                    isRetrying = true
                    Task { await downloads.retry(job); isRetrying = false }
                }
                .disabled(isRetrying || retryUnavailableReason != nil)
                .help(retryUnavailableReason ?? String(localized: "重新获取下载链接并开始下载"))
            } else if job.state == .completed {
                Image(systemName: "checkmark.circle.fill").foregroundStyle(DizzyPalette.success)
            }
        }
        .padding(10)
        .background(.primary.opacity(0.04), in: .rect(cornerRadius: 10))
    }
}

/// 单独的观察边界：高频的字节进度不会触发整行重绘。
private struct DownloadProgressBar: View {
    let job: DownloadJob
    @Environment(DownloadStore.self) private var downloads

    var body: some View {
        if let fraction = downloads.progress(for: job).fraction {
            ProgressView(value: fraction)
                .progressViewStyle(.linear)
                .accessibilityLabel("\(job.title) 下载进度")
                .accessibilityValue(fraction.formatted(.percent.precision(.fractionLength(0))))
        } else {
            ProgressView().progressViewStyle(.linear)
        }
    }
}

/// 下载目录：选择或更换后保存为带安全范围的 bookmark，下载的专辑自动加入本地库。
struct DownloadFolderSection: View {
    @Environment(OfflineLibraryStore.self) private var offline
    @Environment(DownloadStore.self) private var downloads
    @State private var isSelecting = false
    @State private var selectionError: String?

    private var isBusy: Bool { offline.isScanning || isSelecting }
    private var hasActiveDownloads: Bool { downloads.jobs.contains(where: \.isActive) }

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: "folder.fill")
                .font(.title)
                .foregroundStyle(Color.dizzyGold)
            VStack(alignment: .leading, spacing: 4) {
                Text(offline.folderName ?? String(localized: "尚未选择下载目录")).font(.headline)
                Text(offline.folderName == nil
                     ? "选择一个文件夹保存下载的专辑。"
                     : "下载的音乐按 社团 / 专辑 保存在此文件夹，并自动加入本地库。")
                    .foregroundStyle(.secondary)
                if let issue = selectionError ?? offline.downloadFolderIssue {
                    Label(issue, systemImage: "exclamationmark.triangle")
                        .foregroundStyle(Color.dizzyGold)
                }
            }
            Spacer()
            if isBusy { ProgressView().controlSize(.small) }
            Button(offline.folderName == nil ? "选择文件夹…" : "更换…") {
                Task {
                    guard let url = await FolderPanel.chooseFolder(message: String(localized: "选择保存下载专辑的文件夹。")) else { return }
                    isSelecting = true
                    selectionError = nil
                    defer { isSelecting = false }
                    do { try await offline.selectFolder(url) } catch is CancellationError {} catch {
                        selectionError = error.localizedDescription
                    }
                }
            }
            .disabled(isBusy || hasActiveDownloads)
            .help(hasActiveDownloads ? "请先等待下载完成或取消下载" : "选择下载目录")
        }
        .padding(14)
        .background(.primary.opacity(0.04), in: .rect(cornerRadius: 12))
    }
}

/// 下载面板：先确定下载目录，再读取当前会话可用的格式。
struct DownloadSheet: View {
    let detail: DiscDetail
    var isGift = false
    @Environment(OfflineLibraryStore.self) private var offline
    @Environment(DownloadStore.self) private var downloads
    @Environment(\.dismiss) private var dismiss
    @State private var options: [DownloadOption] = []
    @State private var isLoading = false
    @State private var isEnqueuing = false
    @State private var failure: String?

    private var activeJob: DownloadJob? {
        downloads.jobs.first { $0.discID == detail.id && $0.isGift == isGift && $0.isActive }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 12) {
                ArtworkImage(url: detail.summary.coverURL, cornerRadius: 6).frame(width: 52, height: 52)
                VStack(alignment: .leading, spacing: 2) {
                    Text(isGift ? "下载特典" : "下载专辑").font(.headline)
                    Text(detail.summary.title).foregroundStyle(.secondary).lineLimit(2)
                }
            }
            DownloadFolderSection()
            if let activeJob {
                DownloadJobRow(job: activeJob)
            } else if offline.folderName != nil {
                formats
            }
            Spacer(minLength: 0)
            HStack {
                Link("在网页中打开", destination: DizzyURL.disc(detail.id))
                Spacer()
                Button("完成") { dismiss() }
                    .keyboardShortcut(.defaultAction)
            }
        }
        .padding(20)
        .frame(width: 480, height: 460)
        .task(id: offline.folderName) {
            guard offline.folderName != nil else { return }
            await loadOptions()
        }
    }

    @ViewBuilder private var formats: some View {
        if isLoading {
            ProgressView("正在获取可下载格式…").frame(maxWidth: .infinity).padding(.vertical, 16)
        } else if let failure {
            VStack(alignment: .leading, spacing: 8) {
                Text(failure).foregroundStyle(DizzyPalette.danger)
                Button("重试") { Task { await loadOptions() } }
            }
        } else if options.isEmpty {
            Text(isGift ? "暂无可下载的特典，请在专辑网页中确认特典和下载权限。" : "暂时没有可下载的格式，请在专辑网页中确认下载权限。")
                .foregroundStyle(.secondary)
        } else {
            VStack(alignment: .leading, spacing: 8) {
                Text(isGift ? "特典" : "选择格式").font(.headline)
                ForEach(options) { option in
                    Button {
                        isEnqueuing = true
                        Task {
                            await downloads.enqueue(detail: detail, option: option)
                            isEnqueuing = false
                            dismiss()
                        }
                    } label: {
                        HStack {
                            Image(systemName: "arrow.down.circle")
                            Text(option.title)
                            Spacer()
                            Text(isGift ? "下载后自动解压" : option.format.uppercased()).foregroundStyle(.secondary)
                        }
                        .frame(maxWidth: .infinity)
                    }
                    .controlSize(.large)
                    .disabled(isEnqueuing || activeJob != nil || offline.isScanning)
                }
                Text(isGift ? "下载完成后会自动解压到专辑目录的「特典」文件夹。" : "下载完成后会自动解压并加入「本地库」。可在专辑页查看进度。")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private func loadOptions() async {
        guard !isLoading, options.isEmpty, activeJob == nil else { return }
        isLoading = true
        failure = nil
        defer { isLoading = false }
        do {
            let result = try await DizzyPages.shared.downloadOptions(discID: detail.id, gift: isGift)
            try Task.checkCancellation()
            options = result
        } catch is CancellationError {
            return
        } catch {
            guard !Task.isCancelled else { return }
            failure = error.localizedDescription
        }
    }
}
