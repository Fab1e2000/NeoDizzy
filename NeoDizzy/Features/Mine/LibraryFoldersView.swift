import SwiftUI
import UniformTypeIdentifiers

struct LibraryFoldersView: View {
    @Environment(OfflineLibraryStore.self) private var library
    @State private var choosing = false
    @State private var replacing: UUID?
    @State private var isChanging = false
    @State private var issue: String?

    var body: some View {
        List {
            Section("下载目录") { OfflineFolderSection().listRowInsets(EdgeInsets()) }
            Section {
                ForEach(library.scanFolders) { folder in
                    VStack(alignment: .leading, spacing: 8) {
                        Label(folder.name, systemImage: "folder")
                        if let issue = folder.issue {
                            Text(issue).font(.caption).foregroundStyle(DizzyPalette.accent)
                        }
                        HStack {
                            Button("重新授权") { replacing = folder.id; choosing = true }
                            Spacer()
                            Button("移除", role: .destructive) {
                                isChanging = true
                                Task { await library.removeScanFolder(folder.id); isChanging = false }
                            }
                        }
                        .buttonStyle(.borderless)
                        .font(.caption)
                    }
                }
                Button("添加扫描目录", systemImage: "folder.badge.plus") {
                    replacing = nil
                    choosing = true
                }
            } header: { Text("其他扫描目录") } footer: {
                Text("扫描只读取音乐文件。移除目录不会删除文件；下载目录始终包含在本地库中。")
            }
            .disabled(isChanging || library.isScanning)
            Section {
                Button("重新扫描", systemImage: "arrow.clockwise") { Task { await library.scan() } }
                    .disabled(isChanging || library.isScanning)
                if isChanging || library.isScanning { ProgressView("正在读取文件夹…") }
                if let issue = issue ?? library.issue {
                    Text(issue).font(.caption).foregroundStyle(DizzyPalette.accent)
                }
            }
        }
        .safeAreaPadding(.top, 5)
        .navigationTitle("扫描目录")
        .navigationBarTitleDisplayMode(.inline)
        .fileImporter(isPresented: $choosing, allowedContentTypes: [.folder]) { result in
            switch result {
            case .success(let url):
                let target = replacing
                isChanging = true
                issue = nil
                Task {
                    defer { isChanging = false }
                    do { try await library.addScanFolder(url, replacing: target) }
                    catch { issue = error.localizedDescription }
                }
            case .failure(let error): issue = error.localizedDescription
            }
        }
    }
}

