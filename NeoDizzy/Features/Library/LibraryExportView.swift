import SwiftUI
import UniformTypeIdentifiers

struct LibraryConfigurationDocument: FileDocument {
    static var readableContentTypes: [UTType] { [.json] }
    let data: Data
    init(data: Data) { self.data = data }
    init(configuration: ReadConfiguration) throws { data = configuration.file.regularFileContents ?? Data() }
    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper { FileWrapper(regularFileWithContents: data) }
}

struct LibraryExportButton: View {
    @State private var presented = false
    var body: some View {
        Button("导出资料库配置", systemImage: "square.and.arrow.up") { presented = true }
            .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
            .sheet(isPresented: $presented) { LibraryExportSheet() }
    }
}

private struct LibraryExportSheet: View {
    @Environment(FavoritesStore.self) private var favorites
    @Environment(AccountLibraryMirror.self) private var mirror
    @Environment(SavedLibraryStore.self) private var saved
    @Environment(OfflineLibraryStore.self) private var offline
    @Environment(NeteaseStore.self) private var netease
    @Environment(\.dismiss) private var dismiss
    @State private var preparing = false
    @State private var progress = ""
    @State private var document: LibraryConfigurationDocument?
    @State private var exporting = false
    @State private var failure: String?
    @State private var incomplete = 0
    @State private var operation: Task<Void, Never>?
    @State private var exported = false

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Text("导出喜欢、在线专辑和歌单、本地歌单及歌曲列表，保留歌曲顺序、来源和元数据。")
                    Text("文件不包含音频或登录凭据。在线专辑和歌单的歌曲列表将在导出前读取。")
                        .foregroundStyle(.secondary)
                }
                Section {
                    if preparing { ProgressView(progress.isEmpty ? "正在准备配置文件" : progress) }
                    if let failure { Text(failure).foregroundStyle(.red) }
                    if incomplete > 0 {
                        Text("有 \(incomplete) 个在线集合未能读取完整歌曲列表，已在文件中标记。可保存当前结果，或联网后重新准备。")
                    }
                    if exported { Label("配置文件已导出", systemImage: "checkmark.circle") }
                    Button(document == nil ? "准备导出" : "重新准备") { prepare() }
                        .disabled(preparing)
                    if document != nil {
                        Button("保存配置文件", systemImage: "square.and.arrow.down") { exporting = true }
                            .disabled(preparing)
                    }
                }
            }
            .navigationTitle("导出资料库配置")
            .toolbar { ToolbarItem(placement: .cancellationAction) {
                Button(preparing ? "取消" : "完成") { operation?.cancel(); dismiss() }
            } }
            .fileExporter(isPresented: $exporting, document: document, contentType: .json,
                          defaultFilename: "NeoDizzy-资料库-\(Date.now.formatted(.iso8601.year().month().day().dateSeparator(.dash)))") { result in
                switch result {
                case .success: exported = true
                case .failure(let error): failure = error.localizedDescription
                }
            }
            .onDisappear { operation?.cancel() }
        }
    }

    private func prepare() {
        preparing = true; failure = nil; document = nil; incomplete = 0; exported = false
        operation = Task {
            defer { preparing = false }
            var snapshot = LibraryExport.snapshot(favorites: favorites, mirror: mirror, saved: saved, offline: offline)
            do {
                try await snapshot.loadOnlineSongs(netease: netease) { current, total in
                    progress = "正在读取歌曲列表 \(current)/\(total)"
                }
                try Task.checkCancellation()
                incomplete = snapshot.collections.filter { !$0.songsComplete }.count
                document = LibraryConfigurationDocument(data: try snapshot.data())
            } catch is CancellationError {
            } catch { failure = error.localizedDescription }
        }
    }
}
