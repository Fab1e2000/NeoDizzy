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
                Button("从文件导入", systemImage: "square.and.arrow.down") { isPickingFiles = true }
                    .disabled(library.isImporting)
                Button("重新扫描", systemImage: "arrow.clockwise") { Task { await library.scan() } }
                    .disabled(library.isScanning || library.isImporting)
                if library.isImporting {
                    ProgressView("正在导入…")
                } else if library.isScanning {
                    ProgressView("正在读取文件夹…")
                }
                if let message = library.importMessage {
                    Text(message).font(.caption).foregroundStyle(DizzyPalette.mutedText)
                }
                if let issue = library.issue {
                    Text(issue).font(.caption).foregroundStyle(DizzyPalette.accent)
                }
            } footer: {
                Text("可以多选歌曲、歌词（.lrc）、封面图片或 ZIP 压缩包。歌曲按专辑标签放进对应文件夹，压缩包会自动解压。")
            }
        }
        .safeAreaPadding(.top, 5)
        .navigationTitle("音乐文件夹")
        .navigationBarTitleDisplayMode(.inline)
        .musicImporter(isPresented: $isPickingFiles, library: library)
    }
}
