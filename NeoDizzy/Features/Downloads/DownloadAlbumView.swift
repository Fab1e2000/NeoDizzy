import SwiftUI

/// 下载面板先取得文件夹授权，再读取当前会话可用的格式。
struct DownloadAlbumView: View {
    let detail: DiscDetail
    @Environment(OfflineLibraryStore.self) private var offline
    @Environment(DownloadStore.self) private var downloads
    @Environment(\.dismiss) private var dismiss
    @State private var options: [DownloadOption] = []
    @State private var isLoading = false
    @State private var isEnqueuing = false
    @State private var failure: String?

    private var activeJob: DownloadJob? {
        downloads.jobs.first { $0.discID == detail.id && $0.isActive }
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    Text(detail.summary.title)
                        .font(.title3.bold())
                        .foregroundStyle(DizzyPalette.text)
                    OfflineFolderSection()
                    if let activeJob {
                        DownloadJobRow(job: activeJob)
                    } else if offline.album(id: detail.id) != nil {
                        Label("这张专辑已下载，可在音乐库离线播放。", systemImage: "checkmark.circle.fill")
                            .foregroundStyle(DizzyPalette.success)
                    } else if offline.folderName != nil {
                        formatSelection
                    }
                }
                .padding(20)
            }
            .dizzyPageBackground()
            .navigationTitle("下载专辑")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("完成") { dismiss() }
                }
            }
            .task(id: offline.folderName) {
                guard offline.folderName != nil else { return }
                await loadOptions()
            }
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
            Text("暂时没有可下载的格式，请在专辑网页中确认下载权限。")
                .font(.subheadline)
                .foregroundStyle(DizzyPalette.mutedText)
            Link("在网页中打开", destination: DizzyURL.disc(detail.id))
        } else {
            SectionHeading(title: "选择格式")
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
                            Text(option.format.uppercased())
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
            Text("下载完成后会自动解压并加入「已下载」。可在音乐库查看进度、取消或重试。")
                .font(.caption)
                .foregroundStyle(DizzyPalette.mutedText)
        }
    }

    private func loadOptions() async {
        guard !isLoading, options.isEmpty, activeJob == nil,
              offline.album(id: detail.id) == nil else { return }
        isLoading = true
        failure = nil
        defer { isLoading = false }
        do {
            let result = try await DizzyPages.shared.downloadOptions(discID: detail.id)
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
