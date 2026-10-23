import SwiftUI

/// 下载队列按状态分组：进行中、需要处理、已完成；有任务进行时顶部显示总进度。
struct DownloadQueueSection: View {
    @Environment(DownloadStore.self) private var downloads
    let jobs: [DownloadJob]

    var body: some View {
        let active = jobs.filter(\.isActive)
        let attention = jobs.filter { !$0.isActive && $0.canRetry }
        let finished = jobs.filter { !$0.isActive && !$0.canRetry }
        VStack(alignment: .leading, spacing: 12) {
            if let error = downloads.persistenceError {
                Text(error).foregroundStyle(.red)
                Button("重试保存队列") { downloads.retryPersistence() }
            }
            if jobs.isEmpty {
                ContentUnavailableView("没有下载任务", systemImage: "arrow.down.circle",
                                       description: Text("下载的专辑和歌单会显示在这里，完成后自动加入资料库。"))
            }
            if !active.isEmpty { DownloadQueueSummary(jobs: active) }
            group("进行中", jobs: active)
            group("需要处理", jobs: attention)
            group("已完成", jobs: finished)
        }
    }

    @ViewBuilder private func group(_ title: LocalizedStringKey, jobs: [DownloadJob]) -> some View {
        if !jobs.isEmpty {
            Text(title)
                .font(.footnote)
                .foregroundStyle(DizzyPalette.mutedText)
                .padding(.top, 10)
                .padding(.leading, 14)
                .accessibilityAddTraits(.isHeader)
            ForEach(jobs) { job in
                DownloadJobRow(job: job, showsTransfers: true)
            }
        }
    }
}

/// 进行中任务的数量、合计速度与总进度。
private struct DownloadQueueSummary: View {
    let jobs: [DownloadJob]
    @Environment(DownloadStore.self) private var downloads

    var body: some View {
        let fractions = jobs.map { downloads.progress(for: $0).fraction ?? 0 }
        let overall = fractions.reduce(0, +) / Double(max(fractions.count, 1))
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline) {
                Text("\(jobs.count) 项下载中").font(.headline).foregroundStyle(DizzyPalette.text)
                Spacer()
                TimelineView(.periodic(from: .now, by: 1)) { context in
                    let speed = jobs.flatMap(\.transfers)
                        .filter { $0.state == .downloading }
                        .reduce(0) { $0 + downloads.progress(for: $1).speed(at: context.date) }
                    Text(ByteCountFormatter.string(fromByteCount: Int64(speed), countStyle: .file) + "/s")
                        .font(.subheadline).monospacedDigit().foregroundStyle(DizzyPalette.mutedText)
                }
            }
            ProgressView(value: overall)
                .tint(DizzyPalette.download)
                .accessibilityLabel("总进度")
                .accessibilityValue(overall.formatted(.percent.precision(.fractionLength(0))))
            Text("完成后自动加入资料库")
                .font(.caption).foregroundStyle(DizzyPalette.mutedText)
        }
        .padding(16)
        .background(DizzyPalette.surface, in: .rect(cornerRadius: 16))
        .accessibilityElement(children: .combine)
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
        if !downloads.isAvailable(job.providerID) { return "下载来源不可用" }
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
        .background(isEmbedded ? .clear : DizzyPalette.surface, in: .rect(cornerRadius: 16))
        .accessibilityElement(children: .contain)
        .confirmationDialog(job.isActive ? "取消并删除下载任务？" : "删除下载记录？", isPresented: $confirmsRemoval, titleVisibility: .visible) {
            Button("删除", role: .destructive) { Task { await downloads.remove(job) } }
            Button("取消", role: .cancel) { }
        } message: {
            Text("已保存到资料库的音乐会保留。")
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
                    Text(transfer.summary?.title ?? "下载文件").lineLimit(2)
                    if let artist = transfer.summary?.subtitle { Text(artist).font(.caption).foregroundStyle(.secondary).lineLimit(1) }
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
