#if os(iOS)
import SwiftUI

/// 下载面板：专辑页的「下载到本设备」「管理下载」和下载进度都打开它。
/// 没有进行中的任务时选择格式和特典；开始下载后原地变成进度，关掉面板下载也会继续。
struct DownloadAlbumView: View {
    let detail: DiscDetail
    /// 已经下载过这张专辑时，格式可以不选，只下载特典。
    var isDownloaded = false
    @Environment(OfflineLibraryStore.self) private var offline
    @Environment(DownloadStore.self) private var downloads
    @Environment(\.dismiss) private var dismiss
    @AppStorage("downloads.dizzylab.format") private var preferredFormat = "FLAC"
    @State private var formats: [DownloadOption] = []
    @State private var gift: DownloadOption?
    @State private var selectedFormat: String?
    @State private var includesGift = true
    @State private var isLoading = false
    @State private var didLoad = false
    @State private var isEnqueuing = false
    @State private var failure: String?
    /// 在面板里开始的任务，结束后仍显示结果，不跳回选择。
    @State private var trackedJobIDs: Set<UUID> = []

    private var progressJobs: [DownloadJob] {
        downloads.jobs
            .filter { $0.discID == detail.id && ($0.isActive || trackedJobIDs.contains($0.id)) }
            .sorted { !$0.isGift && $1.isGift }
    }
    private var selectedOption: DownloadOption? { formats.first { $0.format == selectedFormat } }
    private var queuesGift: Bool { includesGift && gift != nil }

    var body: some View {
        let jobs = progressJobs
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                header
                if jobs.isEmpty {
                    selection
                } else {
                    DownloadProgressPanel(jobs: jobs)
                }
            }
            .padding(20)
        }
        .scrollBounceBehavior(.basedOnSize)
        .safeAreaInset(edge: .bottom) {
            footer(jobs)
                .padding(.horizontal, 20)
                .padding(.bottom, 8)
        }
        .dizzyPageBackground()
        .presentationDetents([.fraction(0.8), .large])
        .presentationDragIndicator(.visible)
        .task(id: jobs.isEmpty) {
            if jobs.isEmpty { await loadOptions() }
        }
    }

    private var header: some View {
        HStack(spacing: 12) {
            ArtworkImage(url: detail.summary.coverURL, cornerRadius: 8)
                .frame(width: 52, height: 52)
            VStack(alignment: .leading, spacing: 2) {
                Text(detail.summary.title)
                    .font(.headline)
                    .foregroundStyle(DizzyPalette.text)
                    .lineLimit(2)
                Text([detail.summary.labelName, "\(detail.tracks.count) 首"].compactMap { $0 }.joined(separator: " · "))
                    .font(.footnote)
                    .foregroundStyle(DizzyPalette.mutedText)
                    .lineLimit(1)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            Button { dismiss() } label: {
                Image(systemName: "xmark")
                    .font(.subheadline.weight(.bold))
                    .foregroundStyle(DizzyPalette.mutedText)
                    .frame(width: 32, height: 32)
                    .background(.fill.tertiary, in: .circle)
                    .frame(width: 44, height: 44)
                    .contentShape(.rect)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("关闭")
        }
    }

    @ViewBuilder
    private var selection: some View {
        if isLoading || !didLoad {
            ContentSkeleton(layout: .rows, count: 3)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 20)
        } else if let failure {
            LoadFailureView(message: failure) {
                await loadOptions()
            }
        } else if formats.isEmpty && gift == nil {
            Text("暂时没有可下载的内容，请确认已购买并拥有下载权限。")
                .font(.subheadline)
                .foregroundStyle(DizzyPalette.mutedText)
        } else {
            if !formats.isEmpty {
                section("格式", note: isDownloaded && gift != nil ? "已经下载过这张专辑。不选格式就只下载特典。" : nil) {
                    ForEach(Array(formats.enumerated()), id: \.element.id) { index, option in
                        if index > 0 { Divider().padding(.leading, 16) }
                        formatRow(option)
                    }
                }
            }
            if gift != nil {
                section("附加内容") {
                    Toggle(isOn: $includesGift) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("特典")
                                .foregroundStyle(DizzyPalette.text)
                            Text("解压到专辑目录的「特典」文件夹")
                                .font(.caption)
                                .foregroundStyle(DizzyPalette.mutedText)
                        }
                    }
                    .tint(DizzyPalette.download)
                    .padding(.horizontal, 16)
                    .frame(minHeight: 60)
                }
            }
            Label("保存到「\(UIDevice.current.userInterfaceIdiom == .pad ? "我的 iPad" : "我的 iPhone") › NeoDizzy」，完成后自动解压并加入资料库。",
                  systemImage: "folder")
                .font(.caption)
                .foregroundStyle(DizzyPalette.mutedText)
                .padding(.horizontal, 4)
        }
    }

    private func section(_ title: String, note: String? = nil, @ViewBuilder content: () -> some View) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.footnote.weight(.semibold))
                .foregroundStyle(DizzyPalette.mutedText)
                .padding(.horizontal, 4)
            VStack(spacing: 0, content: content)
                .background(DizzyPalette.surface, in: .rect(cornerRadius: 14))
            if let note {
                Text(note)
                    .font(.caption)
                    .foregroundStyle(DizzyPalette.mutedText)
                    .padding(.horizontal, 4)
            }
        }
    }

    private func formatRow(_ option: DownloadOption) -> some View {
        let isSelected = option.format == selectedFormat
        return Button {
            selectedFormat = isSelected && isDownloaded ? nil : option.format
        } label: {
            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(Self.name(of: option))
                        .font(.body.weight(.semibold))
                        .foregroundStyle(DizzyPalette.text)
                    if let note = Self.note(for: option.format) {
                        Text(note)
                            .font(.caption)
                            .foregroundStyle(DizzyPalette.mutedText)
                    }
                }
                Spacer(minLength: 8)
                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                    .font(.title3)
                    .foregroundStyle(isSelected ? DizzyPalette.download : Color(.tertiaryLabel))
            }
            .padding(.horizontal, 16)
            .frame(minHeight: 60)
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }

    @ViewBuilder
    private func footer(_ jobs: [DownloadJob]) -> some View {
        if !jobs.isEmpty {
            if jobs.contains(where: \.isActive) {
                HStack(spacing: 10) {
                    Button(role: .destructive) {
                        for job in jobs where job.isActive { downloads.cancel(job) }
                        trackedJobIDs.subtract(jobs.map(\.id))
                    } label: { Text("取消下载").frame(maxWidth: .infinity) }
                    .buttonStyle(.bordered)
                    .foregroundStyle(DizzyPalette.danger)
                    Button { dismiss() } label: { Text("后台继续").frame(maxWidth: .infinity) }
                    .buttonStyle(.borderedProminent)
                    .tint(DizzyPalette.download)
                }
                .controlSize(.large)
                .buttonBorderShape(.capsule)
                .fontWeight(.semibold)
            } else if jobs.contains(where: \.canRetry) {
                HStack(spacing: 10) {
                    Button { dismiss() } label: { Text("完成").frame(maxWidth: .infinity) }
                        .buttonStyle(.bordered)
                    Button { Task { await retry(jobs) } } label: { Text("重试").frame(maxWidth: .infinity) }
                        .buttonStyle(.borderedProminent)
                        .tint(DizzyPalette.download)
                        .disabled(isEnqueuing || offline.isScanning)
                }
                .controlSize(.large)
                .buttonBorderShape(.capsule)
                .fontWeight(.semibold)
            } else {
                Button { dismiss() } label: { Text("完成").frame(maxWidth: .infinity) }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)
                    .buttonBorderShape(.capsule)
                    .tint(DizzyPalette.download)
                    .fontWeight(.semibold)
            }
        } else if didLoad && !isLoading && failure == nil && !(formats.isEmpty && gift == nil) {
            Button { Task { await start() } } label: {
                Text(startTitle).frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .buttonBorderShape(.capsule)
            .tint(DizzyPalette.download)
            .fontWeight(.semibold)
            .disabled(isEnqueuing || offline.isScanning || (selectedOption == nil && !queuesGift))
        }
    }

    private var startTitle: String {
        switch (selectedOption, queuesGift) {
        case (let option?, true): "下载 \(Self.name(of: option)) + 特典"
        case (let option?, false): "下载 \(Self.name(of: option))"
        case (nil, true): "下载特典"
        case (nil, false): "选择要下载的内容"
        }
    }

    private func start() async {
        isEnqueuing = true
        defer { isEnqueuing = false }
        var queued: [DownloadOption] = []
        if let selectedOption {
            queued.append(selectedOption)
            preferredFormat = selectedOption.format
        }
        if queuesGift, let gift { queued.append(gift) }
        for option in queued {
            await downloads.enqueue(detail: detail, option: option)
            if let job = downloads.jobs.first(where: { $0.discID == detail.id && $0.isGift == option.isGift && $0.isActive }) {
                trackedJobIDs.insert(job.id)
            }
        }
    }

    /// 重试会换成新的任务，跟踪新任务，面板才不会跳回选择。
    private func retry(_ jobs: [DownloadJob]) async {
        isEnqueuing = true
        defer { isEnqueuing = false }
        for job in jobs where job.canRetry {
            trackedJobIDs.remove(job.id)
            await downloads.retry(job)
            if let replacement = downloads.jobs.first(where: { $0.discID == detail.id && $0.isGift == job.isGift && $0.isActive }) {
                trackedJobIDs.insert(replacement.id)
            }
        }
    }

    private func loadOptions() async {
        guard !isLoading, formats.isEmpty, gift == nil else { return }
        isLoading = true
        failure = nil
        defer { isLoading = false; didLoad = true }
        do {
            let result = try await DizzyPages.shared.downloadChoices(discID: detail.id)
            try Task.checkCancellation()
            formats = result.formats
            gift = result.gift
            if !isDownloaded {
                selectedFormat = (formats.first { $0.format == preferredFormat } ?? formats.first { $0.format == "FLAC" } ?? formats.first)?.format
            }
        } catch is CancellationError {
            return
        } catch {
            guard !Task.isCancelled else { return }
            failure = error.localizedDescription
        }
    }

    /// 网站的链接文字为空时，选项标题就是格式代号，「128」单看不明白。
    private static func name(of option: DownloadOption) -> String {
        option.title == "128" ? "MP3 128k" : option.title
    }

    private static func note(for format: String) -> String? {
        switch format {
        case "FLAC": "无损压缩 · 适合收藏"
        case "MP3": "有损 · 兼容性最好"
        case "128": "低码率 · 体积最小"
        default: nil
        }
    }
}

/// 面板里的进度：主任务（专辑优先）分步显示，其余任务（通常是特典）各占一行。
private struct DownloadProgressPanel: View {
    let jobs: [DownloadJob]
    @Environment(DownloadStore.self) private var downloads

    var body: some View {
        if let primary = jobs.first {
            VStack(alignment: .leading, spacing: 12) {
                VStack(alignment: .leading, spacing: 14) {
                    heading(primary)
                    if primary.state == .downloading, let fraction = downloads.progress(for: primary).fraction {
                        ProgressView(value: fraction)
                            .tint(DizzyPalette.download)
                            .accessibilityLabel("\(primary.title) 下载进度")
                            .accessibilityValue(fraction.formatted(.percent.precision(.fractionLength(0))))
                    }
                    if let step = primary.dizzyStep {
                        VStack(alignment: .leading, spacing: 0) {
                            ForEach(Array(DownloadJob.dizzySteps(isGift: primary.isGift).enumerated()), id: \.offset) { index, title in
                                stepRow(title, index: index, current: step)
                            }
                        }
                    } else {
                        Text(primary.statusText)
                            .font(.subheadline)
                            .foregroundStyle(DizzyPalette.mutedText)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    ForEach(jobs.dropFirst()) { job in
                        Divider()
                        secondaryRow(job)
                    }
                }
                .padding(16)
                .background(DizzyPalette.surface, in: .rect(cornerRadius: 14))
                if jobs.contains(where: \.isActive) {
                    Text("关掉面板下载也会继续，进度显示在专辑页和下载队列里。")
                        .font(.caption)
                        .foregroundStyle(DizzyPalette.mutedText)
                        .padding(.horizontal, 4)
                }
            }
        }
    }

    private func heading(_ job: DownloadJob) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Text(title(job))
                .font(.headline)
                .foregroundStyle(DizzyPalette.text)
                .frame(maxWidth: .infinity, alignment: .leading)
            if job.state == .downloading, let fraction = downloads.progress(for: job).fraction {
                Text(fraction.formatted(.percent.precision(.fractionLength(0))))
                    .font(.title.weight(.bold).monospacedDigit())
                    .foregroundStyle(DizzyPalette.download)
                    .accessibilityHidden(true)
            }
        }
    }

    private func title(_ job: DownloadJob) -> String {
        switch job.state {
        case .completed where !job.canRetry: job.isGift ? "特典已下载" : "已下载到本设备"
        case .cancelled: "下载已取消"
        case .failed, .completed: "下载没有完成"
        default: job.isGift ? "正在下载特典" : "正在下载专辑"
        }
    }

    private func stepRow(_ title: String, index: Int, current: Int) -> some View {
        HStack(spacing: 12) {
            Group {
                if index < current {
                    Image(systemName: "checkmark.circle.fill").foregroundStyle(DizzyPalette.success)
                } else if index == current {
                    ProgressView().controlSize(.small)
                } else {
                    Image(systemName: "circle").foregroundStyle(Color(.tertiaryLabel))
                }
            }
            .font(.title3)
            .frame(width: 24, height: 24)
            Text(title)
                .font(.subheadline.weight(index == current ? .semibold : .regular))
                .foregroundStyle(index == current ? DizzyPalette.text : DizzyPalette.mutedText)
        }
        .frame(minHeight: 36)
        .accessibilityElement(children: .combine)
        .accessibilityValue(index < current ? "已完成" : index == current ? "进行中" : "等待")
    }

    private func secondaryRow(_ job: DownloadJob) -> some View {
        HStack(spacing: 12) {
            Image(systemName: job.isGift ? "gift" : "opticaldisc")
                .font(.body)
                .foregroundStyle(DizzyPalette.mutedText)
                .frame(width: 24)
            VStack(alignment: .leading, spacing: 2) {
                Text(job.isGift ? "特典" : "专辑")
                    .font(.subheadline)
                    .foregroundStyle(DizzyPalette.text)
                Text(job.state == .queued ? "排在前面的任务之后" : job.statusText)
                    .font(.caption)
                    .foregroundStyle(job.canRetry ? DizzyPalette.danger : DizzyPalette.mutedText)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            if job.state == .downloading, let fraction = downloads.progress(for: job).fraction {
                Text(fraction.formatted(.percent.precision(.fractionLength(0))))
                    .font(.subheadline.monospacedDigit())
                    .foregroundStyle(DizzyPalette.download)
            }
        }
        .accessibilityElement(children: .combine)
    }
}

/// 专辑页卡片里的下载进度，整行可点，打开下载面板。
struct DownloadEntryProgress: View {
    let job: DownloadJob
    let open: () -> Void
    @Environment(DownloadStore.self) private var downloads

    var body: some View {
        let fraction = job.state == .downloading ? downloads.progress(for: job).fraction : nil
        Button(action: open) {
            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 10) {
                    ProgressView().controlSize(.small)
                    VStack(alignment: .leading, spacing: 1) {
                        Text(job.isGift ? "正在下载特典" : "正在下载专辑")
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(.primary)
                        Text(job.dizzyStepCaption)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    if let fraction {
                        Text(fraction.formatted(.percent.precision(.fractionLength(0))))
                            .font(.headline.monospacedDigit())
                            .foregroundStyle(DizzyPalette.download)
                    }
                    Image(systemName: "chevron.right")
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(.tertiary)
                }
                if let fraction {
                    ProgressView(value: fraction).tint(DizzyPalette.download)
                }
            }
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .combine)
        .accessibilityHint("打开下载进度")
    }
}

extension DownloadJob {
    /// DizzyLab 一次下载的四步。
    static func dizzySteps(isGift: Bool) -> [String] {
        ["获取下载链接", "下载压缩包", "解压", isGift ? "保存到「特典」文件夹" : "加入资料库"]
    }

    /// 当前在第几步；全部完成是 4，失败或取消时不知道停在哪一步，返回 nil。
    var dizzyStep: Int? {
        switch state {
        case .queued, .preparing: 0
        case .downloading: 1
        case .extracting: 2
        case .importing: 3
        case .completed: canRetry ? nil : 4
        case .cancelled, .failed: nil
        }
    }

    var dizzyStepCaption: String {
        guard state != .queued, let step = dizzyStep, step < 4 else { return statusText }
        return "\(Self.dizzySteps(isGift: isGift)[step]) · 第 \(step + 1)/4 步"
    }
}

#endif
