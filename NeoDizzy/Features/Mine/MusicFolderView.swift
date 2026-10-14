import SwiftUI

/// 「音乐文件夹」：App 自己的文件夹就是本地库，下载和导入都存在这里，不需要授权外部文件夹。
struct MusicFolderView: View {
    @Environment(OfflineLibraryStore.self) private var library
    @Environment(\.openURL) private var openURL
    @State private var isPickingFiles = false

    var body: some View {
        List {
            Section {
                Label("我的 iPhone › NeoDizzy", systemImage: "folder")
                if let link = FilesAppLink.libraryFolder {
                    Button("在「文件」中打开", systemImage: "arrow.up.forward.app") { openURL(link) }
                }
            } header: { Text("位置") } footer: {
                Text("下载的专辑保存在这里。也可以在「文件」App 中把音乐拖进这个文件夹，或在电脑的访达里选中 iPhone，从「文件」标签拖进来。每个文件夹显示为一张专辑。")
            }
            Section {
                MusicImportButton(isPresented: $isPickingFiles)
                Button {
                    Task { await library.scan() }
                } label: {
                    HStack {
                        Label(library.isScanning ? "正在扫描音乐…" : "重新扫描", systemImage: "arrow.clockwise")
                        Spacer()
                        if library.isScanning { ProgressView().accessibilityHidden(true) }
                    }
                }
                .disabled(library.isScanning || library.isImporting)
                MusicLibraryStatus()
            } footer: {
                Text("可以多选歌曲、歌词（.lrc）、封面图片或 ZIP 压缩包。歌曲按专辑标签放进对应文件夹，压缩包会自动解压。")
            }
        }
        .scrollContentBackground(.hidden)
        .dizzyPageBackground()
        .safeAreaPadding(.top, 5)
        .navigationTitle("音乐文件夹")
        .navigationBarTitleDisplayMode(.inline)
        .musicImporter(isPresented: $isPickingFiles, library: library)
    }
}

/// 导入入口共用同一操作状态，选择文件后仍可在当前页看到反馈。
struct MusicImportButton: View {
    @Binding var isPresented: Bool
    @Environment(OfflineLibraryStore.self) private var library

    var body: some View {
        Button { isPresented = true } label: {
            HStack(spacing: 12) {
                Label {
                    VStack(alignment: .leading, spacing: 3) {
                        Text(library.isImporting ? "正在导入音乐…" : "导入音乐")
                        Text(library.isImporting ? "正在复制文件并更新本地库" : library.isScanning ? "正在更新本地库，请稍候" : "从「文件」中选择歌曲或压缩包")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                } icon: {
                    Image(systemName: "square.and.arrow.down")
                }
                Spacer(minLength: 0)
                if library.isImporting || library.isScanning { ProgressView().accessibilityHidden(true) }
            }
            .padding(.vertical, 4)
        }
        .disabled(library.isImporting || library.isScanning)
    }
}

struct MusicLibraryStatus: View {
    @Environment(OfflineLibraryStore.self) private var library

    var body: some View {
        if !library.isImporting && !library.isScanning {
            if let message = library.importMessage {
                Text(message)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .textSelection(.enabled)
            }
            if let issue = library.issue {
                Label(issue, systemImage: "exclamationmark.triangle")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
    }
}
