import SwiftUI

/// 设置页「音乐库」分组：导入备份、自动备份和导出。
struct LibraryBackupSection: View {
    @Environment(LibraryBackup.self) private var backup
    var body: some View {
        Section {
            LibraryContextReader { LibraryImportButton(context: $0) }
            NavigationLink(value: AppRoute.page { LibraryBackupSettingsView() }) {
                LabeledContent {
                    Text(backup.interval.title)
                } label: {
                    Label("自动备份", systemImage: "clock.arrow.circlepath")
                }
            }
            LibraryExportButton()
        } header: {
            Text("音乐库")
        }
    }
}

/// 从环境里取齐导出和导入要用的资料库与设置。
private struct LibraryContextReader<Content: View>: View {
    @Environment(FavoritesStore.self) private var favorites
    @Environment(AccountLibraryMirror.self) private var mirror
    @Environment(SavedLibraryStore.self) private var saved
    @Environment(OfflineLibraryStore.self) private var offline
    @Environment(LibraryProviderRegistry.self) private var providers
    @Environment(ModuleSettings.self) private var modules
    @Environment(DownloadStore.self) private var downloads
    @ViewBuilder var content: (LibraryContext) -> Content
    var body: some View {
        content(LibraryContext(favorites: favorites, mirror: mirror, saved: saved, offline: offline,
                               providers: providers, modules: modules, downloads: downloads))
    }
}

/// 点一下就扫描 Backup 文件夹并合并进资料库，不经过文件选择器（重签名的 App 打不开它）。
private struct LibraryImportButton: View {
    let context: LibraryContext
    @Environment(LibraryBackup.self) private var backup
    @State private var importing = false
    @State private var result: ImportResult?
    @State private var failure: String?

    var body: some View {
        Button {
            restore()
        } label: {
            HStack {
                Label("导入备份", systemImage: "square.and.arrow.down")
                if importing { Spacer(); ProgressView() }
            }
        }
        .disabled(importing)
        .sheet(item: $result) { LibraryImportResultSheet(result: $0) }
        .alert("无法导入", isPresented: Binding(get: { failure != nil }, set: { if !$0 { failure = nil } })) {
            Button("好") { failure = nil }
        } message: { Text(failure ?? "") }
    }

    private func restore() {
        importing = true
        Task {
            defer { importing = false }
            do {
                let (export, url) = try backup.findBackup()
                let report = try await context.restore(export, includeSettings: true)
                // 旧备份已经用过，之后的自动备份可以覆盖它。
                backup.markBackedUp()
                result = ImportResult(fileName: url.lastPathComponent, exportedAt: export.exportedAt, report: report)
            } catch { failure = error.localizedDescription }
        }
    }
}

private struct ImportResult: Identifiable {
    let id = UUID()
    let fileName: String
    let exportedAt: Date
    let report: LibraryRestoreReport
}

private struct LibraryImportResultSheet: View {
    let result: ImportResult
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    LabeledContent("文件", value: result.fileName)
                    LabeledContent("备份时间", value: result.exportedAt.formatted(date: .abbreviated, time: .shortened))
                }
                Section {
                    ForEach(result.report.lines, id: \.self) { Text($0) }
                }
            }
            .navigationTitle("已导入备份")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("完成") { dismiss() } } }
        }
    }
}

struct LibraryBackupSettingsView: View {
    @Environment(LibraryBackup.self) private var backup
    @State private var confirmsOverwrite = false

    var body: some View {
        @Bindable var backup = backup
        LibraryContextReader { context in
            List {
                Section {
                    Picker("自动备份", selection: $backup.interval) {
                        ForEach(LibraryBackup.Interval.allCases) { Text($0.title).tag($0) }
                    }
                    LabeledContent("位置", value: "NeoDizzy › Backup")
                    if let last = backup.lastBackup {
                        LabeledContent("上次备份", value: last.formatted(date: .abbreviated, time: .shortened))
                    }
                    if backup.hasUnimportedBackup {
                        Text("自动备份已暂停")
                            .foregroundStyle(.secondary)
                    }
                    if let error = backup.lastError { Text(error).foregroundStyle(.red) }
                }
                .listRowBackground(DizzyPalette.surface)

                Section {
                    Toggle("备份平台登录状态", isOn: $backup.includesAccountLogin)
                }
                .listRowBackground(DizzyPalette.surface)

                Section {
                    Button(backup.isRunning ? "正在备份…" : "立即备份") {
                        if backup.hasUnimportedBackup { confirmsOverwrite = true }
                        else { Task { await backup.backup(context) } }
                    }
                    .disabled(backup.isRunning)
                }
                .listRowBackground(DizzyPalette.surface)
            }
            .scrollContentBackground(.hidden)
            .dizzyPageBackground()
            .navigationTitle("自动备份")
            .navigationBarTitleDisplayMode(.inline)
            .confirmationDialog("覆盖之前的备份？", isPresented: $confirmsOverwrite, titleVisibility: .visible) {
                Button("覆盖", role: .destructive) { Task { await backup.backup(context) } }
                Button("取消", role: .cancel) {}
            }
        }
    }
}

/// 导出一份可分享的配置文件（读取在线歌单的完整歌曲列表，不含登录凭据），经分享菜单保存或发送。
struct LibraryExportButton: View {
    @State private var presented = false
    var body: some View {
        Button("导出资料库配置", systemImage: "square.and.arrow.up") { presented = true }
            .sheet(isPresented: $presented) { LibraryContextReader { LibraryExportSheet(context: $0) } }
    }
}

private struct LibraryExportSheet: View {
    let context: LibraryContext
    @Environment(\.dismiss) private var dismiss
    @State private var preparing = false
    @State private var progress = ""
    @State private var file: URL?
    @State private var failure: String?
    @State private var incomplete = 0
    @State private var operation: Task<Void, Never>?

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    if preparing { ProgressView(progress.isEmpty ? "正在准备配置文件" : progress) }
                    if let failure { Text(failure).foregroundStyle(.red) }
                    if incomplete > 0 {
                        Text("\(incomplete) 个在线集合歌曲列表不完整")
                    }
                    Button(file == nil ? "准备导出" : "重新准备") { prepare() }
                        .disabled(preparing)
                    if let file {
                        ShareLink(item: file) { Label("分享配置文件", systemImage: "square.and.arrow.up") }
                            .disabled(preparing)
                    }
                }
            }
            .navigationTitle("导出资料库配置")
            .toolbar { ToolbarItem(placement: .cancellationAction) {
                Button(preparing ? "取消" : "完成") { operation?.cancel(); dismiss() }
            } }
            .onDisappear { operation?.cancel() }
        }
    }

    private func prepare() {
        preparing = true; failure = nil; file = nil; incomplete = 0
        operation = Task {
            defer { preparing = false }
            var snapshot = context.snapshot()
            do {
                try await snapshot.loadOnlineSongs(providers: context.providers) { current, total in
                    progress = "正在读取歌曲列表 \(current)/\(total)"
                }
                try Task.checkCancellation()
                incomplete = snapshot.collections.filter { !$0.songsComplete }.count
                let name = "NeoDizzy-资料库-\(Date.now.formatted(.iso8601.year().month().day().dateSeparator(.dash))).json"
                let url = URL.temporaryDirectory.appending(path: name)
                try snapshot.data().write(to: url, options: .atomic)
                file = url
            } catch is CancellationError {
            } catch { failure = error.localizedDescription }
        }
    }
}
