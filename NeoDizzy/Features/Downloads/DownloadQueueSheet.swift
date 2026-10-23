#if os(iOS)
import SwiftUI

struct DownloadQueueSheet: View {
    @Environment(DownloadStore.self) private var downloads
    @Environment(\.dismiss) private var dismiss
    /// 已完成且没有失败曲目的任务；删除记录不会删除已保存的音乐。
    private var finished: [DownloadJob] { downloads.jobs.filter { $0.state == .completed && !$0.canRetry } }
    var body: some View {
        NavigationStack {
            ScrollView { DownloadQueueSection(jobs: downloads.jobs).padding(.horizontal, 16).padding(.vertical, 8) }
                .dizzyPageBackground()
                .navigationTitle("下载")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) { Button("完成") { dismiss() } }
                    if !finished.isEmpty {
                        ToolbarItem(placement: .primaryAction) {
                            Button("清除已完成") {
                                Task { for job in finished { await downloads.remove(job) } }
                            }
                        }
                    }
                }
        }
    }
}

#endif
