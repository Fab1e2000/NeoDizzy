import AppKit
import UniformTypeIdentifiers

/// 系统的文件夹选择面板。沙盒会为选中的文件夹授予带安全范围的访问权限，
/// 之后由 `OfflineLibraryStore` 保存为 bookmark。
enum FolderPanel {
    static func chooseFolder(message: String, prompt: String = String(localized: "选择")) async -> URL? {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.canCreateDirectories = true
        panel.allowsMultipleSelection = false
        panel.message = message
        panel.prompt = prompt
        return await run(panel)
    }

    static func chooseFile(message: String, types: [UTType]) async -> URL? {
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        panel.message = message
        panel.allowedContentTypes = types
        return await run(panel)
    }

    private static func run(_ panel: NSOpenPanel) async -> URL? {
        await withCheckedContinuation { continuation in
            let finish: (NSApplication.ModalResponse) -> Void = { response in
                continuation.resume(returning: response == .OK ? panel.url : nil)
            }
            if let window = NSApp.keyWindow ?? NSApp.mainWindow, window.attachedSheet == nil {
                panel.beginSheetModal(for: window, completionHandler: finish)
            } else {
                panel.begin(completionHandler: finish)
            }
        }
    }
}
