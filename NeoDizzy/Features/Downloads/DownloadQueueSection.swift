import SwiftUI

struct DownloadQueueSection: View {
    let jobs: [DownloadJob]

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionHeading(title: "下载队列")
            if jobs.isEmpty {
                ContentUnavailableView("没有下载任务", systemImage: "arrow.down.circle")
            }
            ForEach(jobs) { job in
                DownloadJobRow(job: job, showsTransfers: true)
            }
        }
    }
}

struct DownloadJobRow: View {
    let job: DownloadJob
    /// 放在专辑页的购买卡片里时不再画自己的底色。
    var isEmbedded = false
    var showsTransfers = false
    @State private var showsCompletedTransfers = false
    @Environment(DownloadStore.self) private var downloads
    @Environment(OfflineLibraryStore.self) private var offline
    @State private var isRetrying = false
    @State private var confirmsRemoval = false

    private var retryUnavailableReason: String? {
        if offline.folderName == nil { return "请先选择音乐文件夹" }
        if downloads.jobs.contains(where: { $0.identity == job.identity && $0.isActive }) {
            return "这张专辑已有下载任务"
        }
        if offline.isScanning { return "请等待文件夹扫描完成" }
        return nil
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .top, spacing: 12) {
                if !isEmbedded {
                    ArtworkImage(url: job.coverURL).frame(width: 48, height: 48)
                }
                VStack(alignment: .leading, spacing: 4) {
                    Text(job.title)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(isEmbedded ? Color.primary : DizzyPalette.text)
                        .lineLimit(2)
                    Text(job.statusText)
                        .font(.caption)
                        .foregroundStyle(job.canRetry ? DizzyPalette.accent : DizzyPalette.mutedText)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                if job.isActive {
                    Button("取消", role: .destructive) { downloads.cancel(job) }
                        .buttonStyle(.bordered)
                        .accessibilityLabel("取消下载 \(job.title)")
                } else if job.canRetry {
                    Button("重试") {
                        isRetrying = true
                        Task {
                            await downloads.retry(job)
                            isRetrying = false
                        }
                    }
                    .buttonStyle(.bordered)
                    .disabled(isRetrying || retryUnavailableReason != nil)
                    .accessibilityLabel("重新下载 \(job.title)")
                    .accessibilityHint(retryUnavailableReason ?? "重新获取下载链接并开始下载")
                }
                Menu {
                    if job.isActive {
                        Button("取消下载", systemImage: "xmark.circle", role: .destructive) { downloads.cancel(job) }
                    }
                    Button(job.isActive ? "取消并删除任务" : "删除记录", systemImage: "trash", role: .destructive) {
                        confirmsRemoval = true
                    }
                } label: {
                    Image(systemName: "ellipsis").frame(minWidth: 44, minHeight: 44)
                }
                .accessibilityLabel("下载任务操作：\(job.title)")
            }
            if job.isActive {
                DownloadJobProgressView(job: job)
            }
            if showsTransfers && !job.transfers.isEmpty {
                if job.isActive {
                    transferRows
                } else {
                    DisclosureGroup("下载明细（\(job.transfers.count)）", isExpanded: $showsCompletedTransfers) {
                        transferRows
                    }.font(.subheadline)
                }
            }
        }
        .padding(isEmbedded ? 0 : 14)
        .background(isEmbedded ? .clear : DizzyPalette.surface, in: .rect(cornerRadius: 12))
        .accessibilityElement(children: .contain)
        .confirmationDialog(job.isActive ? "取消并删除下载任务？" : "删除下载记录？", isPresented: $confirmsRemoval, titleVisibility: .visible) {
            Button("删除", role: .destructive) { Task { await downloads.remove(job) } }
            Button("取消", role: .cancel) { }
        } message: {
            Text("已保存到本地库的音乐会保留。")
        }
    }
    private var transferRows: some View {
        LazyVStack(spacing: 12) {
            ForEach(Array(job.transfers.enumerated()), id: \.element.id) { index, transfer in
                DownloadTransferRow(transfer: transfer, providerID: job.providerID, jobState: job.state, index: index + 1)
            }
        }.padding(.top, 8)
    }
}

private struct DownloadTransferRow: View {
    let transfer: DownloadTransfer
    let providerID: String
    let jobState: DownloadJob.State
    let index: Int
    @Environment(DownloadStore.self) private var downloads

    private var metadata: NeteaseDownloadMetadata? {
        guard providerID == "netease" else { return nil }
        return try? JSONDecoder().decode(NeteaseDownloadMetadata.self, from: transfer.metadata)
    }
    private var status: String {
        switch transfer.state {
        case .completed: "已保存"
        case .failed: transfer.failure ?? "下载失败"
        case .downloaded: jobState == .cancelled ? "已取消" : "等待处理音频"
        case .processing: jobState == .cancelled ? "已取消" : "正在处理音频"
        case .downloading: jobState == .cancelled ? "已取消" : "正在下载"
        case .queued: jobState == .cancelled ? "已取消" : "等待下载"
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .firstTextBaseline) {
                Text("\(index)").monospacedDigit().foregroundStyle(.secondary)
                VStack(alignment: .leading, spacing: 3) {
                    Text(metadata?.track.title ?? "专辑压缩包").lineLimit(2)
                    if let artist = metadata?.track.artists { Text(artist).font(.caption).foregroundStyle(.secondary).lineLimit(1) }
                }
                Spacer(minLength: 8)
                if transfer.state == .completed {
                    Image(systemName: "checkmark.circle.fill").foregroundStyle(.green).accessibilityLabel("已保存")
                } else { Text(status).font(.caption).foregroundStyle(transfer.state == .failed ? .red : .secondary).lineLimit(2) }
            }
            if transfer.state == .downloading && jobState.isActive {
                DownloadTransferProgress(progress: downloads.progress(for: transfer))
            }
        }.font(.subheadline)
    }
}

private struct DownloadTransferProgress: View {
    let progress: DownloadProgress
    var body: some View {
        VStack(spacing: 5) {
            if let fraction = progress.fraction { ProgressView(value: fraction).tint(DizzyPalette.download) }
            else { ProgressView().frame(maxWidth: .infinity, alignment: .leading) }
            TimelineView(.periodic(from: .now, by: 1)) { context in
                HStack {
                    Text(ByteCountFormatter.string(fromByteCount: progress.receivedBytes, countStyle: .file) +
                         (progress.expectedBytes > 0 ? " / " + ByteCountFormatter.string(fromByteCount: progress.expectedBytes, countStyle: .file) : ""))
                    Spacer()
                    Text(ByteCountFormatter.string(fromByteCount: Int64(progress.speed(at: context.date)), countStyle: .file) + "/s")
                }.font(.caption).monospacedDigit().foregroundStyle(.secondary)
            }
        }
    }
}

/// A separate observation boundary keeps high-frequency progress out of row/page layout.
private struct DownloadJobProgressView: View {
    let job: DownloadJob
    @Environment(DownloadStore.self) private var downloads

    var body: some View {
        if let fraction = downloads.progress(for: job).fraction {
            ProgressView(value: fraction)
                .tint(DizzyPalette.download)
                .accessibilityLabel("\(job.title) 下载进度")
                .accessibilityValue(fraction.formatted(.percent.precision(.fractionLength(0))))
        } else {
            ProgressView()
                .accessibilityLabel(job.statusText)
        }
    }
}
