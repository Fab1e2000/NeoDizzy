import SwiftUI
import UIKit
import UniformTypeIdentifiers

/// 从「文件」选择歌曲、歌词、封面或 ZIP，导入 App 的音乐文件夹。
///
/// 用复制模式（`asCopy`）打开选择器：由系统把文件复制给 App，App 不需要读取原位置的授权。
/// 打开模式依赖签名身份，重签后的安装包里点「打开」会没有反应。复制模式不能选文件夹。
struct MusicImportPicker: UIViewControllerRepresentable {
    /// 选完或取消都会调用；取消时为空数组。
    var onFinish: ([URL]) -> Void

    static let contentTypes: [UTType] = {
        let extensions = AudioFileMatcher.extensions.union(LibraryImporter.sidecarExtensions).union(["zip"])
        var types: [UTType] = [.audio, .zip]
        for ext in extensions.sorted() {
            if let type = UTType(filenameExtension: ext), !types.contains(type) { types.append(type) }
        }
        return types
    }()

    func makeUIViewController(context: Context) -> UIDocumentPickerViewController {
        let picker = UIDocumentPickerViewController(forOpeningContentTypes: Self.contentTypes, asCopy: true)
        picker.allowsMultipleSelection = true
        picker.delegate = context.coordinator
        return picker
    }

    func updateUIViewController(_ picker: UIDocumentPickerViewController, context: Context) {
        context.coordinator.onFinish = onFinish
    }

    func makeCoordinator() -> Coordinator { Coordinator(onFinish: onFinish) }

    final class Coordinator: NSObject, UIDocumentPickerDelegate {
        var onFinish: ([URL]) -> Void

        init(onFinish: @escaping ([URL]) -> Void) { self.onFinish = onFinish }

        func documentPicker(_ controller: UIDocumentPickerViewController, didPickDocumentsAt urls: [URL]) {
            onFinish(urls)
        }

        func documentPickerWasCancelled(_ controller: UIDocumentPickerViewController) {
            onFinish([])
        }
    }
}

extension View {
    /// 弹出导入选择器；选中的文件交给本地库导入。
    func musicImporter(isPresented: Binding<Bool>, library: OfflineLibraryStore) -> some View {
        sheet(isPresented: isPresented) {
            MusicImportPicker { urls in
                // 选择器自己收起时 sheet 的状态不会跟着复位，这里手动复位，下次才能再打开。
                isPresented.wrappedValue = false
                Task { await library.importItems(urls) }
            }
            .ignoresSafeArea()
        }
    }
}

/// 打开「文件」App 并定位到 NeoDizzy 的文件夹。
enum FilesAppLink {
    static var libraryFolder: URL? {
        URL(string: "shareddocuments://" + URL.documentsDirectory.path(percentEncoded: true))
    }
}
