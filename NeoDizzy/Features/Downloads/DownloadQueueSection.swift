import SwiftUI

struct DownloadQueueSection: View {
    let jobs: [DownloadJob]

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionHeading(title: "下载队列")
            ForEach(jobs) { job in
                DownloadJobRow(job: job)
            }
        }
    }
}

struct DownloadJobRow: View {
    let job: DownloadJob
    /// 放在专辑页的购买卡片里时不再画自己的底色。
    var isEmbedded = false
    @Environment(DownloadStore.self) private var downloads
    @Environment(OfflineLibraryStore.self) private var offline
    @State private var isRetrying = false

    private var retryUnavailableReason: String? {
        if offline.folderName == nil { return "请先选择音乐文件夹" }
        if downloads.jobs.contains(where: { $0.discID == job.discID && $0.isGift == job.isGift && $0.isActive }) {
            return "这张专辑已有下载任务"
        }
        if offline.isScanning { return "请等待文件夹扫描完成" }
        return nil
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .top, spacing: 12) {
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
            }
            if job.isActive {
                DownloadJobProgressView(job: job)
            }
        }
        .padding(isEmbedded ? 0 : 14)
        .background(isEmbedded ? .clear : DizzyPalette.surface, in: .rect(cornerRadius: 12))
        .accessibilityElement(children: .contain)
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
