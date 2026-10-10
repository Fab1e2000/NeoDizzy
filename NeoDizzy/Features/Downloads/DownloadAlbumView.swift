import SwiftUI

/// 下载面板：读取当前会话可用的格式，下载到 App 的音乐文件夹。
struct DownloadAlbumView: View {
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
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    Text(detail.summary.title)
                        .font(.title3.bold())
                        .foregroundStyle(DizzyPalette.text)
                    if let activeJob {
                        DownloadJobRow(job: activeJob)
                    } else {
                        formatSelection
                    }
                }
                .padding(20)
            }
            .dizzyPageBackground()
            .safeAreaPadding(.top, 5)
            .navigationTitle(isGift ? "下载特典" : "下载专辑")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("完成") { dismiss() }
                }
            }
            .task { await loadOptions() }
        }
        .tint(DizzyPalette.accent)
    }

    @ViewBuilder
    private var formatSelection: some View {
        if isLoading {
            ProgressView("正在获取可下载格式…")
                .frame(maxWidth: .infinity)
                .padding(.vertical, 20)
        } else if let failure {
            LoadFailureView(message: failure, webURL: DizzyURL.disc(detail.id)) {
                await loadOptions()
            }
        } else if options.isEmpty {
            Text(isGift ? "暂无可下载的特典，请在专辑网页中确认特典和下载权限。" : "暂时没有可下载的格式，请在专辑网页中确认下载权限。")
                .font(.subheadline)
                .foregroundStyle(DizzyPalette.mutedText)
            Link("在网页中打开", destination: DizzyURL.disc(detail.id))
        } else {
            SectionHeading(title: isGift ? "特典" : "选择格式")
            ForEach(options) { option in
                Button {
                    isEnqueuing = true
                    Task {
                        await downloads.enqueue(detail: detail, option: option)
                        isEnqueuing = false
                        dismiss()
                    }
                } label: {
                    HStack(spacing: 12) {
                        Image(systemName: "arrow.down.circle")
                        VStack(alignment: .leading, spacing: 3) {
                            Text(option.title)
                                .font(.headline)
                            Text(isGift ? "下载后自动解压" : option.format.uppercased())
                                .font(.caption)
                                .foregroundStyle(DizzyPalette.mutedText)
                        }
                        Spacer()
                        Image(systemName: "chevron.right")
                            .font(.caption.weight(.semibold))
                    }
                    .padding(16)
                    .contentShape(.rect)
                    .background(DizzyPalette.surface, in: .rect(cornerRadius: 12))
                }
                .buttonStyle(.plain)
                .foregroundStyle(DizzyPalette.download)
                .disabled(isEnqueuing || activeJob != nil || offline.isScanning)
                .accessibilityLabel("下载 \(option.title)")
            }
            Text(isGift ? "下载完成后会自动解压到专辑目录的「特典」文件夹。可在专辑详情中查看进度、取消或重试。" : "下载完成后会自动解压并加入「本地库」。可在专辑详情中查看进度、取消或重试。")
                .font(.caption)
                .foregroundStyle(DizzyPalette.mutedText)
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
